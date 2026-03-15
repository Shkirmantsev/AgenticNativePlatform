module "inventory" {
  source          = "../../modules/inventory-generator"
  topology        = "local"
  control_plane   = {
    name         = "localhost"
    ansible_host = var.local_ansible_host
    ansible_user = var.local_ansible_user
    connection   = "local"
    private_key  = ""
  }
  workers         = []
  metallb_start   = var.metallb_start
  metallb_end     = var.metallb_end
  lmstudio_host_ip = var.lmstudio_host_ip
  lmstudio_port    = var.lmstudio_port
}
