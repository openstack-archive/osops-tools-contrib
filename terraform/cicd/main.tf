output "gerrit" {
    value = "http://${openstack_compute_floatingip_v2.gerrit_floatingip.address}"
}

output "jenkins" {
    value = "http://${openstack_compute_floatingip_v2.jenkins_floatingip.address}"
}

output "redmine" {
    value = "http://${openstack_compute_floatingip_v2.redmine_floatingip.address}"
}
