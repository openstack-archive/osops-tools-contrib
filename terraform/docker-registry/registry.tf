resource "null_resource" "generate_ssl" {
    count = "${var.generate_ssl}"
    provisioner "local-exec" {
        command = "bash files/ssl/generate-ssl.sh"
    }
}

resource "template_file" "registry_vars" {
    template = "templates/registry_vars.env"
    vars {
        extra_vars = "${var.docker_registry_extra_vars}"
        secret = "${var.prefix}"
    }
}

resource "template_file" "local_vars" {
    template = "templates/local_vars.env"
}

resource "template_file" "swift_vars" {
    template = "templates/swift_vars.env"
    vars {
        extra_vars = "${var.docker_registry_swift_extra_vars}"
        username = "${var.swift_username}"
        password = "${var.swift_password}"
        auth_url = "${var.swift_auth_url}"
        tenant = "${var.swift_tenant}"
        container = "${var.swift_container}"
    }
}

resource "openstack_compute_secgroup_v2" "registry" {
    name = "${var.prefix}_docker-registry"
    description = "${var.prefix} Docker Registry"
    rule {
        ip_protocol = "tcp"
        from_port = "443"
        to_port = "443"
        cidr = "${var.whitelist_network}"
    }
    rule {
        ip_protocol = "tcp"
        from_port = "22"
        to_port = "22"
        cidr = "${var.whitelist_network}"
    }
}

resource "openstack_networking_floatingip_v2" "registry" {
    count = "${var.instance_count}"
    pool = "${var.floatingip_pool}"
}

resource "openstack_compute_keypair_v2" "registry" {
    name = "${var.prefix}_docker-registry"
    public_key = "${file(var.public_key_path)}"
}

resource "openstack_compute_instance_v2" "registry" {
    name = "${var.prefix}_docker-registry-${count.index}"
    count = "${var.instance_count}"
    image_name = "${var.image}"
    flavor_name = "${var.flavor}"
    floating_ip = "${element(openstack_networking_floatingip_v2.registry.*.address, count.index)}"
    key_pair = "${openstack_compute_keypair_v2.registry.name}"
    network {
        name = "${var.network_name}"
    }
    security_groups = [
        "${openstack_compute_secgroup_v2.registry.name}",
    ]
    provisioner "file" {
        source = "files"
        destination = "/tmp/files"
        connection {
            user = "${var.ssh_user}"
        }
    }
    provisioner "remote-exec" {
        inline = [
            # Check that Docker is installed.  If not try to install it.
            "if ! which docker; then ",
            "  ${var.docker_install_command}",
            "fi",
            "sudo mkdir -p /opt/docker-registry/{files,ssl,config}",
            # Create TLS certs
            "echo 'subjectAltName = @alt_names' >> /tmp/files/ssl/openssl.cnf",
            "echo '[alt_names]' >> /tmp/files/ssl/openssl.cnf",
            "echo 'IP.1 = 127.0.0.1' >> /tmp/files/ssl/openssl.cnf",
            "echo 'IP.2 = ${self.network.0.fixed_ip_v4}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'IP.3 = ${element(openstack_networking_floatingip_v2.registry.*.address, count.index)}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'DNS.1 = localhost' >> /tmp/files/ssl/openssl.cnf",
            "echo 'DNS.2 = ${var.fqdn}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'DNS.3 = ${element(openstack_networking_floatingip_v2.registry.*.address, count.index)}.xip.io' >> /tmp/files/ssl/openssl.cnf",
            "openssl genrsa -out /tmp/files/ssl/key.pem 2048",
            "openssl req -new -key /tmp/files/ssl/key.pem -out /tmp/files/ssl/cert.csr -subj '/CN=docker-client' -config /tmp/files/ssl/openssl.cnf",
            "openssl x509 -req -in /tmp/files/ssl/cert.csr -CA /tmp/files/ssl/ca.pem -CAkey /tmp/files/ssl/ca-key.pem \\",
            "-CAcreateserial -out /tmp/files/ssl/cert.pem -days 365 -extensions v3_req -extfile /tmp/files/ssl/openssl.cnf",
            "sudo mkdir -p /etc/docker/ssl",
            "sudo cp /tmp/files/ssl/ca.pem /opt/docker-registry/ssl/",
            "sudo cp /tmp/files/ssl/cert.pem /opt/docker-registry/ssl/",
            "sudo cp /tmp/files/ssl/key.pem /opt/docker-registry/ssl/",
            # Create registry env file
            "sudo su -c \"cat <<'EOF' > /opt/docker-registry/config/registry.env\n${template_file.registry_vars.rendered}\nEOF\"",
            "echo XXXXXXXXXXXXXXXX ${var.docker_registry_storage_backend} XXXXXXXXXXXXXXXXXXX",
            "if [ \"${var.docker_registry_storage_backend}\" == \"swift\" ]; then",
            "sudo su -c \"cat <<'EOF' >> /opt/docker-registry/config/registry.env\n${template_file.swift_vars.rendered}\nEOF\"",
            "else",
            "sudo su -c \"cat <<'EOF' >> /opt/docker-registry/config/registry.env\n${template_file.local_vars.rendered}\nEOF\"",
            "fi",
            "docker pull registry:${var.docker_registry_version}",
            "docker run -d --name docker-registry \\",
            "  -v /opt/docker-registry:/opt/docker-registry \\",
            "  -p 443:5000 --restart always \\",
            "  --env-file /opt/docker-registry/config/registry.env \\",
            "  registry:${var.docker_registry_version}",
        ]
        connection {
            user = "${var.ssh_user}"
        }
    }
    depends_on = [
      "template_file.registry_vars",
      "template_file.swift_vars",
    ]
}

output "docker registry host" {
    value = "${openstack_networking_floatingip_v2.registry.0.address}"
}

output "Do the following to use the registry" {
    value = "\n\n$ sudo mkdir -p /etc/docker/certs.d/${openstack_networking_floatingip_v2.registry.0.address}\n$ sudo cp files/ssl/ca.pem /etc/docker/certs.d/${openstack_networking_floatingip_v2.registry.0.address}/ca.crt\n"
}
