resource "openstack_compute_secgroup_v2" "swarm_base" {
  name = "${var.cluster_name}_swarm_base"
  description = "${var.cluster_name} - Docker Swarm Security Group"
  # SSH
  rule {
    ip_protocol = "tcp"
    from_port = "22"
    to_port = "22"
    cidr = "${var.whitelist_network}"
  }
  # DOCKER SWARM
  rule {
    ip_protocol = "tcp"
    from_port = "2375"
    to_port = "2375"
    cidr = "${var.whitelist_network}"
  }
  # DOCKER
  rule {
    ip_protocol = "tcp"
    from_port = "2376"
    to_port = "2376"
    cidr = "${var.whitelist_network}"
  }
  # INTERNAL Communication only
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

  # DANGER DANGER DANGER
  # Uncomment these if you want to allow
  # unrestricted inbound access
  #rule {
  #  ip_protocol = "tcp"
  #  from_port = "1"
  #  to_port = "65535"
  #  cidr = "${var.whitelist_network}"
  #}
  #rule {
  #  ip_protocol = "udp"
  #  from_port = "1"
  #  to_port = "65535"
  #  cidr = "${var.whitelist_network}"
  #}
}
