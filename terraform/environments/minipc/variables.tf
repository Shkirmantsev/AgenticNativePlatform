variable "metallb_start" { type = string }
variable "metallb_end" { type = string }
variable "lmstudio_host_ip" { type = string }
variable "lmstudio_port" { type = number, default = 1234 }

variable "control_plane_ip" { type = string }
variable "control_plane_user" { type = string, default = "ubuntu" }
variable "ssh_private_key" { type = string, default = "~/.ssh/id_ed25519" }
