
resource "openstack_compute_secgroup_v2" "kubernetes_controller" {
  name = "${var.project}_kubernetes_controller"
  description = "kubernetes Controller Security Group"
  rule {
    ip_protocol = "tcp"
    from_port = "1"
    to_port = "65535"
    cidr = "${var.whitelist_network}"
  }
  rule {
    ip_protocol = "icmp"
    from_port = "-1"
    to_port = "-1"
    cidr = "${var.whitelist_network}"
  }
}

resource "openstack_compute_secgroup_v2" "kubernetes_compute" {
  name = "${var.project}_kubernetes_compute"
  description = "kubernetes Compute Security Group"
  rule {
    ip_protocol = "icmp"
    from_port = "-1"
    to_port = "-1"
    cidr = "${var.whitelist_network}"
  }
}

resource "openstack_compute_secgroup_v2" "kubernetes_base" {
  name = "${var.project}_kubernetes_base"
  description = "kubernetes Base Security Group"
  rule {
    ip_protocol = "tcp"
    from_port = "22"
    to_port = "22"
    cidr = "${var.whitelist_network}"
  }
  rule {
    ip_protocol = "icmp"
    from_port = "-1"
    to_port = "-1"
    self = true
  }
  rule {
    ip_protocol = "tcp"
    from_port = "1"
    to_port = "65535"
    self = true
  }
  rule {
    ip_protocol = "udp"
    from_port = "1"
    to_port = "65535"
    self = true
  }
}
