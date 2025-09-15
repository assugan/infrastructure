variable "region"{
    type = string
    default = "eu-central-1"
}

variable "state_bucket"{
    type = string
    default = "assugan-tf-state"
}

variable "lock_table"{
    type = string
    default = "assugan-tf-lock"
}