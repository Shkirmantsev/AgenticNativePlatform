variable "metallb_start" { type = string }
variable "metallb_end" { type = string }
variable "lmstudio_host_ip" { type = string }
variable "lmstudio_port" { type = number, default = 1234 }

variable "local_ansible_host" { type = string, default = "127.0.0.1" }
variable "local_ansible_user" { type = string, default = "dmytro" }
