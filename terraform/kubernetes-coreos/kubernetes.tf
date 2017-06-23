resource "openstack_networking_floatingip_v2" "controller" {
  count = "1"
  pool = "${var.floatingip_pool}"
}

#resource "openstack_networking_floatingip_v2" "compute" {
#  count = "${var.compute_count}"
#  pool = "${var.floatingip_pool}"
#}

resource "openstack_compute_keypair_v2" "kubernetes" {
  name = "${var.project}"
  public_key = "${file(var.public_key_path)}"
}

resource "openstack_compute_instance_v2" "controller" {
    name = "${var.cluster_name}-controller${count.index}"
    count = "1"
    image_name = "${var.kubernetes_image}"
    flavor_name = "${var.kubernetes_flavor}"
    key_pair = "${openstack_compute_keypair_v2.kubernetes.name}"
    network {
        name = "${var.network_name}"
    }
    security_groups = [
        "${openstack_compute_secgroup_v2.kubernetes_base.name}",
        "${openstack_compute_secgroup_v2.kubernetes_controller.name}"
    ]
    floating_ip = "${element(openstack_networking_floatingip_v2.controller.*.address, count.index)}"
    #user_data = "${template_file.controller_cloud_init.rendered}"
    provisioner "file" {
        source = "files"
        destination = "/tmp/stage"
        connection {
          user = "${var.ssh_user}",
          timeout = "8m"
        }
    }
    provisioner "remote-exec" {
        inline = [
          "sudo bash /tmp/stage/install_kube.sh",
          "echo '----> Starting Kubernetes Controller'",
          "sudo kubeadm init --token ${var.kubernetes_token}",
          "echo '----> Installing Weave'",
          "kubectl apply -f https://git.io/weave-kube"
        ]
        connection {
          user = "${var.ssh_user}",
          timeout = "8m"
        }
    }
    depends_on = [
    ]
}

resource "openstack_compute_instance_v2" "compute" {
    name = "${var.cluster_name}-compute${count.index}"
    count = "${var.compute_count}"
    image_name = "${var.kubernetes_image}"
    flavor_name = "${var.kubernetes_flavor}"
    #floating_ip = "${element(openstack_networking_floatingip_v2.compute.*.address, count.index)}"
    key_pair = "${openstack_compute_keypair_v2.kubernetes.name}"
    network {
        name = "${var.network_name}"
    }
    security_groups = [
        "${openstack_compute_secgroup_v2.kubernetes_base.name}",
        "${openstack_compute_secgroup_v2.kubernetes_compute.name}"
    ]
    provisioner "file" {
        source = "files"
        destination = "/tmp/stage"
        connection {
            user = "${var.ssh_user}"
            bastion_host = "${openstack_networking_floatingip_v2.controller.0.address}"
        }
    }
    provisioner "remote-exec" {
        inline = [
          "sudo bash /tmp/stage/install_kube.sh",
          "echo '----> Joining K8s Controller'",
          "sudo kubeadm join --token ${var.kubernetes_token} ${openstack_compute_instance_v2.controller.0.network.0.fixed_ip_v4}"
        ]
        connection {
            user = "${var.ssh_user}"
            bastion_host = "${openstack_networking_floatingip_v2.controller.0.address}"
        }
    }
    depends_on = [
        "openstack_compute_instance_v2.controller"
    ]
}

output "kubernetes-controller" {
    value = "$ ssh -A ${var.ssh_user}@${openstack_networking_floatingip_v2.controller.0.address}"
}
