resource "null_resource" "discovery_url" {
    count = "${var.generate_discovery_url}"
    provisioner "local-exec" {
        command = "curl -s 'https://discovery.etcd.io/new?size=${var.cluster_size}' > files/discovery_url"
    }
}

resource "null_resource" "update_cloud_init" {
    provisioner "local-exec" {
        command = "sed -i \"s|^    discovery:.*$|    discovery: $(cat files/discovery_url)|\" files/cloud-init"
    }
    depends_on = [
        "null_resource.discovery_url"
    ]
}

resource "null_resource" "generate_ssh_keys" {
    provisioner "local-exec" {
        command = "if [ ! -e keys/${var.deis_keyname} ]; then ssh-keygen -f keys/${var.deis_keyname} -P ''; fi"
    }
}

resource "openstack_networking_floatingip_v2" "deis" {
    count = "${var.cluster_size}"
    pool = "${var.floatingip_pool}"
}

resource "openstack_compute_keypair_v2" "deis" {
    name = "${var.cluster_name}-deis"
    public_key = "${file(var.public_key_path)}"
}

resource "openstack_compute_secgroup_v2" "deis" {
    name = "${var.cluster_name}-deis"
    description = "Deis Security Group"
    rule {
        ip_protocol = "tcp"
        from_port = "22"
        to_port = "22"
        cidr = "0.0.0.0/0"
    }
    rule {
        ip_protocol = "tcp"
        from_port = "2222"
        to_port = "2222"
        cidr = "0.0.0.0/0"
    }
    rule {
        ip_protocol = "tcp"
        from_port = "80"
        to_port = "80"
        cidr = "0.0.0.0/0"
    }
    rule {
        ip_protocol = "icmp"
        from_port = "-1"
        to_port = "-1"
        cidr = "0.0.0.0/0"
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

resource "openstack_compute_instance_v2" "deis" {
    name = "${var.cluster_name}-deis-${count.index+1}"
    count = "${var.cluster_size}"
    image_name = "${var.image}"
    flavor_id = "${var.flavor}"
    key_pair = "${openstack_compute_keypair_v2.deis.name}"
    user_data = "${file("files/cloud-init")}"
    network {
        name = "${var.network_name}"
    }
    security_groups = [ "${openstack_compute_secgroup_v2.deis.name}" ]
    floating_ip = "${element(openstack_networking_floatingip_v2.deis.*.address, count.index)}"
    provisioner "file" {
        source = "keys/"
        destination = "/home/core/.ssh/"
        connection {
            user = "core"
        }
    }
    provisioner "remote-exec" {
        inline = [
            "chown core:core /home/core/.ssh/${var.deis_keyname}*",
            "chmod 0600 /home/core/.ssh/${var.deis_keyname}",
            "cat /home/core/.ssh/${var.deis_keyname}.pub >> /home/core/.ssh/authorized_keys",
        ]
        connection {
            user = "core"
        }
    }
    depends_on = [
        "null_resource.update_cloud_init",
        "null_resource.generate_ssh_keys"
    ]
}

resource "null_resource" "install_deis" {
   provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /opt/bin",
            "if [[ ! -e /opt/bin/deictl ]]; then curl -sSL http://deis.io/deisctl/install.sh | sudo sh -s ${var.deisctl_version}; fi",
            "export DOMAIN=${var.deis_domain}",
            "if [[ -z $DOMAIN ]]; then export DOMAIN=${openstack_networking_floatingip_v2.deis.0.address}.xip.io; fi",
            "/opt/bin/deisctl config platform set domain=$DOMAIN",
            "/opt/bin/deisctl config platform set sshPrivateKey=/home/core/.ssh/${var.deis_keyname}",
            "/opt/bin/deisctl install platform",
            "/opt/bin/deisctl start platform",
        ]
        connection {
            user = "core"
            host = "${openstack_networking_floatingip_v2.deis.0.address}"
        }
    }
    depends_on = [
        "openstack_compute_instance_v2.deis",
    ]
}


output "msg" {
    value = "Your hosts are ready to go! Continue following the documentation to install and start Deis. Your hosts are: ${join(", ", openstack_networking_floatingip_v2.deis.*.address )}"
}

output "register" {
    value = "Run the following to register your first [admin] user: $ deis register http://deis.${openstack_networking_floatingip_v2.deis.0.address}.xip.io"
}

