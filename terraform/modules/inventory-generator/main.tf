terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

locals {
  inventory = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    control_plane = var.control_plane
    workers       = var.workers
  })

  metallb_values = yamlencode({
    metallb = {
      pool = {
        start = var.metallb_start
        end   = var.metallb_end
      }
    }
  })

  node_labels_env = join("
", concat([
    "CONTROL_PLANE_NAME=${var.control_plane.name}",
    "CONTROL_PLANE_IP=${var.control_plane.ansible_host}",
    "LMSTUDIO_HOST_IP=${var.lmstudio_host_ip}",
    "LMSTUDIO_PORT=${var.lmstudio_port}",
  ], [for w in var.workers : "WORKER_${upper(replace(w.name, "-", "_"))}=${w.ansible_host}"]))

  lmstudio_endpoint = yamlencode({
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata   = { name = "lmstudio-external", namespace = "ai-gateway" }
    subsets    = [{ addresses = [{ ip = var.lmstudio_host_ip }], ports = [{ port = var.lmstudio_port }] }]
  })

  topology_values = yamlencode({
    topology = {
      name = var.topology
      controlPlane = var.control_plane
      workers = var.workers
      lmstudio = { host = var.lmstudio_host_ip, port = var.lmstudio_port }
      metallb = { start = var.metallb_start, end = var.metallb_end }
    }
  })
}

resource "local_file" "inventory" {
  filename = "${path.root}/../../../ansible/generated/${var.topology}.ini"
  content  = local.inventory
}

resource "local_file" "metallb_values" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/metallb-values.yaml"
  content  = local.metallb_values
}

resource "local_file" "node_labels_env" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/node-labels.env"
  content  = local.node_labels_env
}

resource "local_file" "lmstudio_endpoint" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/lmstudio-endpoint.yaml"
  content  = local.lmstudio_endpoint
}

resource "local_file" "topology_values" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/topology-values.yaml"
  content  = local.topology_values
}
