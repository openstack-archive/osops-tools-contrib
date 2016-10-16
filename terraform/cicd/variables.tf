variable "image" {
  default = "ubuntu-14.04-cloud"
}

variable "flavor" {
  default = "m2.large"
}

variable "external_gateway" {
  default  = "7004a83a-13d3-4dcd-8cf5-52af1ace4cae"
}

variable "floating_pool" {
  default = "GATEWAY_NET"
}

# Redmine Configuration values
variable "redmine_version" {
  default = "3.3.0"
}

variable "root_db_password"{
  default = "secure"
}

variable "redmine_db_password"{
  default = "secure"
}
