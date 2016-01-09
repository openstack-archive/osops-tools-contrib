variable "image" {
    description = "Name of glance image to use"
    default = "coreos"
}

variable "prefix" {
    description = "prefix of openstack resources"
    default = "example"
}

variable "instance_count" {
    description = "Number of servers to run.  If you change this you will need to set up some sort of data replication for the registry files."
    default = 1
}

variable "network_name" {
    default = "internal"
}

variable "floatingip_pool" {
    default = "external"
}

variable "flavor" {
    default = "m1.small"
}

variable "ssh_user" {
    default = "core"
}

variable "docker_registry_version" {
    description = "version of docker registry to use. Should be 2 or higher."
    default = "2"
}

variable "docker_registry_extra_vars" {
    description = "extra ENV vars to use when starting registry"
    default = "REGISTRY_HTTP_TLS_CLIENTCAS_0=/opt/docker-registry/ssl/ca.pem"
}

variable "docker_registry_swift_extra_vars" {
    description = "extra ENV vars for swift to use when starting registry"
    default = ""
}

variable "docker_registry_storage_backend" {
    description = "storage backend to use for docker registry [local|swift]"
    default = "local"
}

variable "docker_install_command" {
    description = "If docker is not found, this command will be run"
    default = "sudo apt-get update && sudo apt-get -y install curl && curl -sSL get.docker.com | sudo bash"
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

variable "generate_ssl" {
  descripion = "set to 1 to regenerate SSL certificates/keys"
  default = 1
}

variable "fqdn" {
    description = "FQDN for certificate"
    default = "registry.local"
}

variable "swift_username" {
  description = "Your openstack username"
  default = ""
}

variable "swift_password" {
  description = "Your openstack password"
  default = ""
}

variable "swift_tenant" {
  description = "Your openstack tenant/project"
  default = ""
}

variable "swift_auth_url" {
  description = "Your openstack auth URL"
  default = ""
}

variable "swift_container" {
  description = "swift container for docker registry"
  default = "docker_registry"
}
