locals {
  k3s_image = "rancher/k3s:${replace(var.k3s_version, "+", "-")}"
}

module "k3d_config" {
  source         = "../../modules/k3d-config-generator"
  topology       = "github-codespace"
  cluster_name   = var.workspace_cluster_name
  k3s_image      = local.k3s_image
  cluster_domain = var.cluster_domain
}
