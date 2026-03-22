locals {
  k3s_image = "rancher/k3s:${replace(var.k3s_version, "+", "-")}"
}

module "k3d_config" {
  source         = "../../modules/k3d-config-generator"
  topology       = "github-workspace"
  cluster_name   = var.workspace_cluster_name
  k3s_image      = local.k3s_image
  cluster_domain = var.cluster_domain
}

module "flux_manifests" {
  source                            = "../../modules/flux-manifest-generator"
  topology                          = "github-workspace"
  environment                       = var.environment
  runtime                           = var.runtime
  secrets_mode                      = var.secrets_mode
  platform_profile                  = var.platform_profile
  include_local_bootstrap_artifacts = false
  lmstudio_enabled                  = var.lmstudio_enabled
  platform_root_timeout             = var.platform_root_timeout
  platform_bootstrap_timeout        = var.platform_bootstrap_timeout
  platform_infra_timeout            = var.platform_infra_timeout
  platform_apps_timeout             = var.platform_apps_timeout
  git_repo_url                      = var.git_repo_url
  git_branch                        = var.git_branch
  enable_weave_gitops_ui            = var.enable_weave_gitops_ui
  enable_samples_echo_mcp           = var.enable_samples_echo_mcp
  gemini_model                      = var.gemini_model
  lmstudio_chat_model               = var.lmstudio_chat_model
  lmstudio_embedding_model          = var.lmstudio_embedding_model
  embedding_model                   = var.embedding_model
  ollama_version                    = var.ollama_version
  ollama_default_model              = var.ollama_default_model
  vllm_model                        = var.vllm_model
  vllm_image_repository             = var.vllm_image_repository
  vllm_image_tag                    = var.vllm_image_tag
  vllm_cpu_kvcache_space            = var.vllm_cpu_kvcache_space
  vllm_cpu_num_of_reserved_cpu      = var.vllm_cpu_num_of_reserved_cpu
  vllm_ld_preload                   = var.vllm_ld_preload
  echo_mcp_image                    = var.echo_mcp_image
  lmstudio_port                     = var.lmstudio_port
}
