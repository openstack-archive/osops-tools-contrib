resource "null_resource" "discovery_url_template" {
    count = "${var.generate_discovery_url}"
    provisioner "local-exec" {
        command = "curl -s 'https://discovery.etcd.io/new?size=${var.cluster_size}' > templates/discovery_url"
    }
}

resource "null_resource" "generate_ssl" {
    count = "${var.generate_ssl}"
    provisioner "local-exec" {
        command = "bash files/ssl/generate-ssl.sh"
    }
}

resource "template_file" "discovery_url" {
    template = "templates/discovery_url"
    depends_on = [
        "null_resource.discovery_url_template"
    ]
}

resource "template_file" "cloud_init" {
    template = "templates/cloud-init"
    vars {
        flannel_network = "${var.flannel_network}"
        flannel_backend = "${var.flannel_backend}"
        cluster_token = "${var.cluster_name}"
        discovery_url = "${template_file.discovery_url.rendered}"
    }
}

resource "template_file" "10_docker_service" {
    template = "templates/10-docker-service.conf"
}

resource "openstack_networking_floatingip_v2" "coreos" {
  count = "${var.cluster_size}"
  pool = "${var.floatingip_pool}"
}

resource "openstack_compute_keypair_v2" "coreos" {
  name = "swarm-${var.cluster_name}"
  public_key = "${file(var.public_key_path)}"
}

resource "openstack_compute_instance_v2" "coreos" {
    name = "swarm-${var.cluster_name}-${count.index}"
    count = "${var.cluster_size}"
    image_name = "${var.image_name}"
    flavor_name = "${var.flavor}"
    key_pair = "${openstack_compute_keypair_v2.coreos.name}"
    network {
        name = "${var.network_name}"
    }
    security_groups = [
        "${openstack_compute_secgroup_v2.swarm_base.name}"
    ]
    floating_ip = "${element(openstack_networking_floatingip_v2.coreos.*.address, count.index)}"
    user_data = "${template_file.cloud_init.rendered}"
    provisioner "file" {
        source = "files"
        destination = "/tmp/files"
        connection {
            user = "core"
        }
    }
    provisioner "remote-exec" {
        inline = [
            # Create TLS certs
            "mkdir -p /home/core/.docker",
            "cp /tmp/files/ssl/ca.pem /home/core/.docker/",
            "cp /tmp/files/ssl/cert.pem /home/core/.docker/",
            "cp /tmp/files/ssl/key.pem /home/core/.docker/",
            "echo 'subjectAltName = @alt_names' >> /tmp/files/ssl/openssl.cnf",
            "echo '[alt_names]' >> /tmp/files/ssl/openssl.cnf",
            "echo 'IP.1 = ${self.network.0.fixed_ip_v4}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'IP.2 = ${element(openstack_networking_floatingip_v2.coreos.*.address, count.index)}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'DNS.1 = ${var.fqdn}' >> /tmp/files/ssl/openssl.cnf",
            "echo 'DNS.2 = ${element(openstack_networking_floatingip_v2.coreos.*.address, count.index)}.xip.io' >> /tmp/files/ssl/openssl.cnf",
            "openssl req -new -key /tmp/files/ssl/key.pem -out /tmp/files/ssl/cert.csr -subj '/CN=docker-client' -config /tmp/files/ssl/openssl.cnf",
            "openssl x509 -req -in /tmp/files/ssl/cert.csr -CA /tmp/files/ssl/ca.pem -CAkey /tmp/files/ssl/ca-key.pem \\",
            "-CAcreateserial -out /tmp/files/ssl/cert.pem -days 365 -extensions v3_req -extfile /tmp/files/ssl/openssl.cnf",

            "docker run --rm -v /tmp/files/ssl:/certs \\",
            "  -e SSL_IP=${self.network.0.fixed_ip_v4},${element(openstack_networking_floatingip_v2.coreos.*.address, count.index)} \\",
            "  -e SSL_SUBJECT=${element(openstack_networking_floatingip_v2.coreos.*.address, count.index)}.xip.io \\",
            "  paulczar/omgwtfssl",
            "sudo mkdir -p /etc/docker/ssl",
            "sudo cp /tmp/files/ssl/ca.pem /etc/docker/ssl/",
            "sudo cp /tmp/files/ssl/cert.pem /etc/docker/ssl/",
            "sudo cp /tmp/files/ssl/key.pem /etc/docker/ssl/",
            # Apply TLS to docker service
            "sudo mkdir -p /etc/systemd/system/docker.service.d",
            "cat <<'EOF' > /tmp/10-tls-verify.conf\n${template_file.10_docker_service.rendered}\nEOF",
            "sudo mv /tmp/10-tls-verify.conf /etc/systemd/system/docker.service.d/10-tls-verify.conf",
            "sudo systemctl daemon-reload",
            "sudo systemctl restart docker.service",
            # Run docker swarm
            "docker pull swarm:${var.swarm_version}",
            "docker run -d --name swarm-agent \\",
            "  swarm:${var.swarm_version} \\",
            "  join --addr=${self.network.0.fixed_ip_v4}:2376 \\",
            "  etcd://${self.network.0.fixed_ip_v4}:2379/swarm",
            "docker run -d --name swarm-manager -v /etc/docker/ssl:/etc/docker/ssl --net=host \\",
            "  swarm:${var.swarm_version} manage \\",
            "  --tlsverify --tlscacert=/etc/docker/ssl/ca.pem --tlscert=/etc/docker/ssl/cert.pem \\",
            "  --tlskey=/etc/docker/ssl/key.pem etcd://${self.network.0.fixed_ip_v4}:2379/swarm"
        ]
        connection {
            user = "core"
        }
    }
    depends_on = [
        "template_file.cloud_init"
    ]
}

resource "null_resource" "post_install" {
   provisioner "remote-exec" {
        inline = [
            "echo test",
        ]
        connection {
            user = "core"
            host = "${openstack_networking_floatingip_v2.coreos.0.address}"
        }
    }
    depends_on = [
        "openstack_compute_instance_v2.coreos",
    ]
}

output "swarm_cluster" {
    value = "\nEnvironment Variables for accessing Docker Swarm via floating IP of first host:\nexport DOCKER_HOST=tcp://${openstack_networking_floatingip_v2.coreos.0.address}:2375\nexport DOCKER_TLS_VERIFY=1\nexport DOCKER_CERT_PATH=${path.module}/files/ssl"
}
