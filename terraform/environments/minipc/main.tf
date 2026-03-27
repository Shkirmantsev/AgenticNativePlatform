module "inventory" {
  source   = "../../modules/inventory-generator"
  topology = "minipc"
  environment = var.environment
  control_plane = {
    name         = "minipc"
    ansible_host = var.control_plane_ip
    ansible_user = var.control_plane_user
    private_key  = var.ssh_private_key
  }
  workers          = []
  metallb_start    = var.metallb_start
  metallb_end      = var.metallb_end
  lmstudio_host_ip = var.lmstudio_host_ip
  lmstudio_port    = var.lmstudio_port
}
