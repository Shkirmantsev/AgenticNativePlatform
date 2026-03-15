module "inventory" {
  source          = "../../modules/inventory-generator"
  topology        = "hybrid"
  control_plane   = {
    name         = "minipc"
    ansible_host = var.control_plane_ip
    ansible_user = var.control_plane_user
    private_key  = var.ssh_private_key
  }
  workers         = [{
    name         = "workstation"
    ansible_host = var.worker_ip
    ansible_user = var.worker_user
    private_key  = var.ssh_private_key
  }]
  metallb_start   = var.metallb_start
  metallb_end     = var.metallb_end
  lmstudio_host_ip = var.lmstudio_host_ip
  lmstudio_port    = var.lmstudio_port
}
