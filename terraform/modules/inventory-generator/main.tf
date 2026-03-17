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

  lmstudio_endpoint = yamlencode({
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata   = { name = "lmstudio-external", namespace = "ai-gateway" }
    subsets    = [{ addresses = [{ ip = var.lmstudio_host_ip }], ports = [{ port = var.lmstudio_port }] }]
  })

  lmstudio_values = <<-EOT
hostIP: ${var.lmstudio_host_ip}
port: ${var.lmstudio_port}
EOT

  lmstudio_values_configmap = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata   = { name = "lmstudio-values", namespace = "flux-system" }
    data       = { "values.yaml" = local.lmstudio_values }
  })

  metallb_resources = join("\n---\n", [
    yamlencode({
      apiVersion = "metallb.io/v1beta1"
      kind       = "IPAddressPool"
      metadata   = { name = "primary-pool", namespace = "metallb-system" }
      spec       = { addresses = ["${var.metallb_start}-${var.metallb_end}"] }
    }),
    yamlencode({
      apiVersion = "metallb.io/v1beta1"
      kind       = "L2Advertisement"
      metadata   = { name = "primary-pool", namespace = "metallb-system" }
      spec       = { ipAddressPools = ["primary-pool"] }
    })
  ])

  topology_values = yamlencode({
    topology = {
      name         = var.topology
      controlPlane = var.control_plane
      workers      = var.workers
      lmstudio     = { host = var.lmstudio_host_ip, port = var.lmstudio_port }
      metallb      = { start = var.metallb_start, end = var.metallb_end }
    }
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

resource "local_file" "generated_kustomization" {
  filename = "${path.root}/../../../flux/generated/${var.topology}/kustomization.yaml"
  content  = <<-EOT
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - metallb-values.yaml
  - lmstudio-endpoint.yaml
  - lmstudio-values-configmap.yaml
EOT
}
