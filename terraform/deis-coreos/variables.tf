variable "cluster_size" {
  default = "3"
}

variable "cluster_name" {
  default = "example"
}

variable "flavor" {
  default = "m1.medium"
}

variable "public_key_path" {
  description = "The path of the ssh pub key"
  default = "~/.ssh/id_rsa.pub"
}

variable "image" {
  description = "the image to use"
  default = "coreos"
}

variable "network_name" {
  description = "name of the internal network to use"
  default = "internal"
}

variable "floatingip_pool" {
  description = "name of the floating ip pool to use"
  default = "external"
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

variable "generate_discovery_url" {
    default = 1
    description = "set to 0 if you do not want to autogenerate the discovery url"
}

variable "deisctl_version" {
    default = "1.12.2"
}

variable "deis_domain" {
  default = ""
  description =  "set if you have a custom domain"
}

variable "deis_keyname" {
  default = "deis"
}
