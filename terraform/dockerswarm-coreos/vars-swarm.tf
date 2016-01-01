variable "cluster_size" {
    default = 3
}

variable "cluster_name" {
    default = "testing"
}

variable "swarm_version" {
    default = "latest"
}

variable "generate_ssl" {
  description = "set to 0 if you want to reuse ssl certs"
  default = 1
}

variable "fqdn" {
  description = "Fully Qualified DNS to add to TLS certs"
  default = "swarm.example.com"
}
