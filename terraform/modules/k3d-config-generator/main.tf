terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

locals {
  k3d_config = templatefile("${path.module}/templates/k3d-cluster.yaml.tftpl", {
    cluster_name   = var.cluster_name
    k3s_image      = var.k3s_image
    cluster_domain = var.cluster_domain
  })
}

resource "local_file" "k3d_config" {
  filename = "${path.root}/../../../.generated/k3d/${var.topology}.yaml"
  content  = local.k3d_config
}
