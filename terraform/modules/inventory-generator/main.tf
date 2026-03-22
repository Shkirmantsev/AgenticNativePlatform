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

  control_plane_metadata = merge(var.control_plane, {
    connection  = lookup(var.control_plane, "connection", "")
    private_key = lookup(var.control_plane, "private_key", "")
  })

  worker_metadata = [
    for worker in var.workers : merge(worker, {
      connection  = lookup(worker, "connection", "")
      private_key = lookup(worker, "private_key", "")
    })
  ]

  lmstudio_endpoint = templatefile("${path.module}/templates/lmstudio-endpoint.yaml.tftpl", {
    lmstudio_host_ip = var.lmstudio_host_ip
    lmstudio_port    = var.lmstudio_port
  })

  lmstudio_values_configmap = templatefile("${path.module}/templates/lmstudio-values-configmap.yaml.tftpl", {
    lmstudio_host_ip = var.lmstudio_host_ip
    lmstudio_port    = var.lmstudio_port
  })

  metallb_resources = templatefile("${path.module}/templates/metallb-values.yaml.tftpl", {
    metallb_start = var.metallb_start
    metallb_end   = var.metallb_end
  })

  topology_values = templatefile("${path.module}/templates/topology-values.yaml.tftpl", {
    topology      = var.topology
    control_plane = local.control_plane_metadata
    workers       = local.worker_metadata
    lmstudio_host = var.lmstudio_host_ip
    lmstudio_port = var.lmstudio_port
    metallb_start = var.metallb_start
    metallb_end   = var.metallb_end
  })
}

resource "local_file" "inventory" {
  filename = "${path.root}/../../../ansible/generated/${var.topology}.ini"
  content  = local.inventory
}

resource "local_file" "metallb_resources" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/metallb-values.yaml"
  content  = local.metallb_resources
}

resource "local_file" "lmstudio_endpoint" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/lmstudio-endpoint.yaml"
  content  = local.lmstudio_endpoint
}

resource "local_file" "topology_values" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/topology-values.yaml"
  content  = local.topology_values
}

resource "local_file" "lmstudio_values_configmap" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/lmstudio-values-configmap.yaml"
  content  = local.lmstudio_values_configmap
}
