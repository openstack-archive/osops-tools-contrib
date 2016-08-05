# The terraform to stand up LAMP stack

resource "openstack_compute_keypair_v2" "lampstack_key" {
  name = "lampstack_key"
  public_key = "${file(var.public_key_path)}"
}

resource "openstack_compute_secgroup_v2" "lampstack_sg" {
  name = "lampstack_sg"
  description = "lampstack security group"
  rule {
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
  rule {
    from_port = 80
    to_port = 80
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
  rule {
    from_port = 3306
    to_port = 3306
    ip_protocol = "tcp"
    cidr = "0.0.0.0/0"
  }
}

resource "openstack_networking_floatingip_v2" "database" {
  count = 1
  pool = "${var.public_net}"
}

resource "openstack_compute_instance_v2" "database" {
  name = "database"
  image_name = "${var.image_name}"
  flavor_name = "${var.flavor}"
  key_pair = "lampstack_key"
  security_groups = ["${openstack_compute_secgroup_v2.lampstack_sg.name}"]
  network {
    name = "${var.private_net}"
  }
  floating_ip = "${openstack_networking_floatingip_v2.database.0.address}"

  connection {
    user = "ubuntu"
    timeout = "30s"
  }

  provisioner "file" {
    source = "onvm"
    destination = "/tmp/onvm"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${self.network.0.fixed_ip_v4} database > /tmp/onvm/hostname",
      "chmod +x /tmp/onvm/scripts/*",
      "/tmp/onvm/scripts/installdb.sh"
    ]
  }
}

resource "openstack_networking_floatingip_v2" "apache" {
    count = "${var.stack_size - 1}"
    pool = "${var.public_net}"
}

resource "openstack_compute_instance_v2" "apache" {
  name = "apache_${count.index}"
  count = "${var.stack_size - 1}"
  image_name = "${var.image_name}"
  flavor_name = "${var.flavor}"
  key_pair = "lampstack_key"
  security_groups = ["${openstack_compute_secgroup_v2.lampstack_sg.name}"]
  network {
    name = "${var.private_net}"
  }
  floating_ip = "${element(openstack_networking_floatingip_v2.apache.*.address, count.index)}"

  depends_on = [ "openstack_compute_instance_v2.database" ]

  connection {
    user = "ubuntu"
    timeout = "30s"
  }

  provisioner "file" {
    source = "onvm"
    destination = "/tmp/onvm"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${openstack_compute_instance_v2.database.network.0.fixed_ip_v4} database > /tmp/onvm/hostname",
      "echo ${self.network.0.fixed_ip_v4} apache-${count.index} >> /tmp/onvm/hostname",
      "chmod +x /tmp/onvm/scripts/*",
      "/tmp/onvm/scripts/installapache.sh"
    ]
  }

}

output "lampstack" {
    value = "Success!!!\n\nAccess service at the following URLs:\nhttp://${join("\nhttp://",openstack_compute_instance_v2.apache.*.floating_ip)}"
}
