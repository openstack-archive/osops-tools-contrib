variable "flannel_backend" {
    default = "vxlan"
}

variable "flannel_network" {
    default = "10.10.0.0/16"
}

variable "generate_discovery_url" {
    default = 1
    description = "set to 0 if you do not want to autogenerate the discovery url"
}
