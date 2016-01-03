variable "flannel_backend" {
    default = "vxlan"
}

variable "flannel_network" {
    default = "10.10.0.0/16"
}

variable "kubernetes_image" {
    default = "kubernetes"
}

variable "project" {}

variable "portal_net" {
    default = "10.200.0.0/16"
}

variable "compute_count" {
    default = 2
}

variable "cluster_name" {
    default = "testing"
}

variable "network_name" {
    default = "internal"
}

variable "floatingip_pool" {
    default = "external"
}

variable "kubernetes_flavor" {
    default = "m1.medium"
}

variable "kubernetes_token" {
    default = "kubernetes"
}

variable "kubernetes_user" {
    default = "admin"
}

variable "username" {
  description = "Your openstack username"
}

variable "password" {
  description = "Your openstack password"
}

variable "tenant" {
  description = "Your openstack tenant/project"
}

variable "auth_url" {
  description = "Your openstack auth URL"
}

variable "public_key_path" {
  description = "The path of the ssh pub key"
  default = "~/.ssh/id_rsa.pub"
}

variable "whitelist_network" {
  description = "network to allow connectivity from"
  default = "0.0.0.0/0"
}

variable "kubectl_version" {
  description = "Version of kubectl binary to download"
  default = "v1.1.2"
}

variable "hyperkube_version" {
  description = "Version of the hypercube container to use"
  default = "v1.1.2"
}

variable "generate_ssl" {
  descripion = "set to 1 to regenerate SSL certificates/keys"
  default = 1
}
