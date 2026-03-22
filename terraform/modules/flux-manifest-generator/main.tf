terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

locals {
  repo_root             = abspath("${path.root}/../../..")
  generated_dir         = "${local.repo_root}/flux/generated/${var.topology}"
  cluster_id            = "${var.topology}-${var.environment}-${var.runtime}-${var.secrets_mode}"
  cluster_generated_dir = "${local.repo_root}/flux/generated/clusters/${local.cluster_id}"
  infra_component       = var.topology == "github-workspace" ? "../../../../components/platform-infrastructure-workspace" : "../../../../components/platform-infrastructure"

  litellm_values_configmap = templatefile("${path.module}/templates/litellm-values-configmap.yaml.tftpl", {
    gemini_model             = var.gemini_model
    lmstudio_chat_model      = var.lmstudio_chat_model
    lmstudio_embedding_model = var.lmstudio_embedding_model
    lmstudio_port            = var.lmstudio_port
    ollama_default_model     = var.ollama_default_model
  })

  tei_values_configmap = templatefile("${path.module}/templates/tei-values-configmap.yaml.tftpl", {
    embedding_model = var.embedding_model
  })

  ollama_values_configmap = templatefile("${path.module}/templates/ollama-values-configmap.yaml.tftpl", {
    ollama_version       = trimprefix(var.ollama_version, "v")
    ollama_default_model = var.ollama_default_model
  })

  vllm_values_configmap = templatefile("${path.module}/templates/vllm-values-configmap.yaml.tftpl", {
    vllm_image_repository        = var.vllm_image_repository
    vllm_image_tag               = var.vllm_image_tag
    vllm_model                   = var.vllm_model
    vllm_cpu_kvcache_space       = var.vllm_cpu_kvcache_space
    vllm_cpu_num_of_reserved_cpu = var.vllm_cpu_num_of_reserved_cpu
    vllm_ld_preload              = var.vllm_ld_preload
  })

  echo_mcp_values_configmap = templatefile("${path.module}/templates/echo-mcp-values-configmap.yaml.tftpl", {
    echo_mcp_image = var.echo_mcp_image
  })

  lmstudio_endpoint = templatefile("${path.module}/../inventory-generator/templates/lmstudio-endpoint.yaml.tftpl", {
    lmstudio_host_ip = var.lmstudio_host_ip
    lmstudio_port    = var.lmstudio_port
  })

  lmstudio_values_configmap = templatefile("${path.module}/../inventory-generator/templates/lmstudio-values-configmap.yaml.tftpl", {
    lmstudio_host_ip = var.lmstudio_host_ip
    lmstudio_port    = var.lmstudio_port
  })

  metallb_values = templatefile("${path.module}/../inventory-generator/templates/metallb-values.yaml.tftpl", {
    metallb_start = var.metallb_start
    metallb_end   = var.metallb_end
  })

  generated_kustomization = templatefile("${path.module}/templates/generated-kustomization.yaml.tftpl", {
    include_local_bootstrap_artifacts = var.include_local_bootstrap_artifacts
  })

  cluster_root_kustomization = templatefile("${path.module}/templates/cluster-root-kustomization.yaml.tftpl", {})

  platform_bootstrap = templatefile("${path.module}/templates/platform-bootstrap.yaml.tftpl", {
    cluster_path               = "./flux/generated/clusters/${local.cluster_id}/bootstrap"
    platform_bootstrap_timeout = var.platform_bootstrap_timeout
    secrets_mode               = var.secrets_mode
  })

  platform_infrastructure = templatefile("${path.module}/templates/platform-infrastructure.yaml.tftpl", {
    cluster_path           = "./flux/generated/clusters/${local.cluster_id}/infrastructure"
    platform_infra_timeout = var.platform_infra_timeout
  })

  platform_applications = templatefile("${path.module}/templates/platform-applications.yaml.tftpl", {
    cluster_path          = "./flux/generated/clusters/${local.cluster_id}/apps"
    platform_apps_timeout = var.platform_apps_timeout
  })

  bootstrap_kustomization = templatefile("${path.module}/templates/bootstrap-kustomization.yaml.tftpl", {
    include_local_bootstrap_artifacts = var.include_local_bootstrap_artifacts
    environment                       = var.environment
    secrets_mode                      = var.secrets_mode
  })

  infrastructure_kustomization = templatefile("${path.module}/templates/infrastructure-kustomization.yaml.tftpl", {
    infra_component  = local.infra_component
    runtime          = var.runtime
    lmstudio_enabled = var.lmstudio_enabled
  })

  apps_kustomization = templatefile("${path.module}/templates/apps-kustomization.yaml.tftpl", {
    environment                       = var.environment
    include_local_bootstrap_artifacts = var.include_local_bootstrap_artifacts
  })

  samples_echo_mcp_kustomization = templatefile("${path.module}/templates/samples-echo-mcp-kustomization.yaml.tftpl", {})

  topology_files = merge(
    {
      "litellm-values-configmap.yaml"  = local.litellm_values_configmap
      "tei-values-configmap.yaml"      = local.tei_values_configmap
      "ollama-values-configmap.yaml"   = local.ollama_values_configmap
      "vllm-values-configmap.yaml"     = local.vllm_values_configmap
      "echo-mcp-values-configmap.yaml" = local.echo_mcp_values_configmap
      "kustomization.yaml"             = local.generated_kustomization
    },
    var.include_local_bootstrap_artifacts ? {
      "lmstudio-endpoint.yaml"         = local.lmstudio_endpoint
      "lmstudio-values-configmap.yaml" = local.lmstudio_values_configmap
      "metallb-values.yaml"            = local.metallb_values
    } : {}
  )

  cluster_files = merge(
    {
      "kustomization.yaml"                                        = local.cluster_root_kustomization
      "platform-bootstrap.yaml"                                   = local.platform_bootstrap
      "platform-infrastructure.yaml"                              = local.platform_infrastructure
      "platform-applications.yaml"                                = local.platform_applications
      "bootstrap/generated-litellm-values-configmap.yaml"         = local.litellm_values_configmap
      "bootstrap/generated-ollama-values-configmap.yaml"          = local.ollama_values_configmap
      "bootstrap/generated-tei-values-configmap.yaml"             = local.tei_values_configmap
      "bootstrap/generated-vllm-values-configmap.yaml"            = local.vllm_values_configmap
      "bootstrap/kustomization.yaml"                              = local.bootstrap_kustomization
      "infrastructure/kustomization.yaml"                         = local.infrastructure_kustomization
      "apps/kustomization.yaml"                                   = local.apps_kustomization
      "samples-echo-mcp/generated-echo-mcp-values-configmap.yaml" = local.echo_mcp_values_configmap
      "samples-echo-mcp/kustomization.yaml"                       = local.samples_echo_mcp_kustomization
    },
    var.include_local_bootstrap_artifacts ? {
      "bootstrap/generated-lmstudio-endpoint.yaml"         = local.lmstudio_endpoint
      "bootstrap/generated-lmstudio-values-configmap.yaml" = local.lmstudio_values_configmap
      "apps/generated-metallb-values.yaml"                 = local.metallb_values
    } : {}
  )
}

resource "local_file" "topology_files" {
  for_each = local.topology_files

  filename = "${local.generated_dir}/${each.key}"
  content  = each.value
}

resource "local_file" "cluster_files" {
  for_each = local.cluster_files

  filename = "${local.cluster_generated_dir}/${each.key}"
  content  = each.value
}
