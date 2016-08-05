variable "image_name" {
    default = "trusty 1404"
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
