module "inventory" {
  source   = "../../modules/inventory-generator"
  topology = "minipc"
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

module "flux_manifests" {
  source                            = "../../modules/flux-manifest-generator"
  topology                          = "minipc"
  environment                       = var.environment
  runtime                           = var.runtime
  secrets_mode                      = var.secrets_mode
  include_local_bootstrap_artifacts = true
  lmstudio_enabled                  = var.lmstudio_enabled
  platform_bootstrap_timeout        = var.platform_bootstrap_timeout
  platform_infra_timeout            = var.platform_infra_timeout
  platform_apps_timeout             = var.platform_apps_timeout
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
  lmstudio_host_ip                  = var.lmstudio_host_ip
  lmstudio_port                     = var.lmstudio_port
  metallb_start                     = var.metallb_start
  metallb_end                       = var.metallb_end
}
