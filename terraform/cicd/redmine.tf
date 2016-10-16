resource "openstack_compute_floatingip_v2" "redmine_floatingip" {
  depends_on = ["openstack_networking_router_interface_v2.router_interface"]
  pool = "${var.floating_pool}"
}

# Template for redmine webserver installation
data "template_file" "redmine_web_postinstall_script" {
  template = "${file("redmine_web.tpl")}"
  vars {
    version = "${var.redmine_version}"
    redmine_db_ip = "${openstack_compute_instance_v2.redmine_db.network.0.fixed_ip_v4}"
    redmine_db_password = "${var.redmine_db_password}"
  }
}

resource "openstack_compute_instance_v2" "redmine" {
  depends_on = ["openstack_compute_instance_v2.redmine_db"]
  name = "redmine"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  security_groups = [ "${openstack_compute_secgroup_v2.secgroup.name}" ]
  floating_ip = "${openstack_compute_floatingip_v2.redmine_floatingip.address}"
  user_data = "${data.template_file.redmine_web_postinstall_script.rendered}"
  network {
    uuid = "${openstack_networking_network_v2.private_network.id}"
  }
}

# Template for redmine database installation
data "template_file" "redmine_db_postinstall_script" {
  template = "${file("redmine_db.tpl")}"
  vars {
    root_db_password = "${var.root_db_password}"
    redmine_db_password = "${var.redmine_db_password}"
  }
}

resource "openstack_compute_instance_v2" "redmine_db" {
  name = "redmine-db"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  user_data = "${data.template_file.redmine_db_postinstall_script.rendered}"

  network {
    uuid = "${openstack_networking_network_v2.private_network.id}"
  }
}
