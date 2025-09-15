variable "region"{
  type = string
  default = "eu-central-1"
}

variable "domain"{
  type = string
  default = "assugan.click"
}

variable "ssh_key_name"{
  type = string
  default = "ssh-diploma-key"
}

variable "instance_type"{
  type = string
  default = "t3.micro"
}

variable "allow_ssh_cidr"{
  type = string
  default = "0.0.0.0/0"
}