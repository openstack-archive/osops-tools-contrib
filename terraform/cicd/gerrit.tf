resource "openstack_compute_floatingip_v2" "gerrit_floatingip" {
  depends_on = ["openstack_networking_router_interface_v2.router_interface"]
  pool = "${var.floating_pool}"
}

# Template for gerrit installation
data "template_file" "gerrit_postinstall_script" {
  template = "${file("gerrit.tpl")}"
  vars {
    password = "secure"
  }
}

resource "openstack_compute_instance_v2" "gerrit" {
  name = "gerrit"
  image_name = "${var.image}"
  flavor_name = "${var.flavor}"
  security_groups = [ "${openstack_compute_secgroup_v2.secgroup.name}" ]
  floating_ip = "${openstack_compute_floatingip_v2.gerrit_floatingip.address}"
  user_data = "${data.template_file.gerrit_postinstall_script.rendered}"

  network {
    uuid = "${openstack_networking_network_v2.private_network.id}"
  }
}
