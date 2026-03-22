variable "topology" { type = string }
variable "control_plane" { type = map(string) }
variable "workers" { type = list(map(string)) }
variable "metallb_start" { type = string }
variable "metallb_end" { type = string }
variable "lmstudio_host_ip" { type = string }
variable "lmstudio_port" { type = number }
