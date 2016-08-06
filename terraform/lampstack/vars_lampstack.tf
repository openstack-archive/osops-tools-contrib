variable "image_name" {
    default = "ubuntu-14.04"
}

variable "private_net" {
    default = "internal"
}

variable "public_net" {
    default = "external"
}

variable "flavor" {
    default = "m1.medium"
}

variable "public_key_path" {
  description = "The path of the ssh pub key"
  default = "~/.ssh/id_rsa.pub"
}

variable "stack_size" {
  default = 3
}

variable "db_username" {
  description = "The lamp stack database user for remote access"
  default = "dbuser"
}

variable "db_password" {
  description = "The lamp stack database user password for remote access"
  default = "dbpass"
}