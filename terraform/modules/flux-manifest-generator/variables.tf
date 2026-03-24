variable "topology" {
  type = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "runtime" {
  type    = string
  default = "none"

  validation {
    condition     = contains(["none", "ollama", "vllm"], var.runtime)
    error_message = "runtime must be one of: none, ollama, vllm."
  }
}

variable "secrets_mode" {
  type    = string
  default = "external"

  validation {
    condition     = contains(["external", "sops"], var.secrets_mode)
    error_message = "secrets_mode must be one of: external, sops."
  }
}

variable "platform_profile" {
  type    = string
  default = ""

  validation {
    condition = var.platform_profile == "" || contains([
      "platform-profile-fast",
      "platform-profile-fast-serving",
      "platform-profile-fast-context",
      "platform-profile-full",
      "platform-profile-workspace",
    ], var.platform_profile)
    error_message = "platform_profile must be empty or one of the supported platform-profile-* names."
  }
}

variable "include_local_bootstrap_artifacts" {
  type    = bool
  default = true
}

variable "lmstudio_enabled" {
  type    = bool
  default = false
}

variable "platform_bootstrap_timeout" {
  type    = string
  default = "10m"
}

variable "platform_root_timeout" {
  type    = string
  default = "30m"
}

variable "platform_infra_timeout" {
  type    = string
  default = "15m"
}

variable "platform_apps_timeout" {
  type    = string
  default = "20m"
}

variable "git_repo_url" {
  type    = string
  default = ""
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "enable_samples_echo_mcp" {
  type    = bool
  default = false
}

variable "gemini_model" {
  type    = string
  default = "gemini-3.1-flash-lite-preview"
}

variable "lmstudio_chat_model" {
  type    = string
  default = "qwen/qwen3-4b"
}

variable "lmstudio_embedding_model" {
  type    = string
  default = "text-embedding-qwen3-embedding-0.6b"
}

variable "embedding_model" {
  type    = string
  default = "onnx-models/all-MiniLM-L6-v2-onnx"
}

variable "ollama_version" {
  type    = string
  default = "v0.18.0"
}

variable "ollama_default_model" {
  type    = string
  default = "qwen2.5:7b-instruct"
}

variable "vllm_model" {
  type    = string
  default = "Qwen/Qwen2.5-0.5B-Instruct"
}

variable "vllm_image_repository" {
  type    = string
  default = "public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo"
}

variable "vllm_image_tag" {
  type    = string
  default = "v0.18.0"
}

variable "vllm_cpu_kvcache_space" {
  type    = string
  default = "2"
}

variable "vllm_cpu_num_of_reserved_cpu" {
  type    = string
  default = "1"
}

variable "vllm_ld_preload" {
  type    = string
  default = ""
}

variable "echo_mcp_image" {
  type    = string
  default = "echo-mcp:local"
}

variable "lmstudio_port" {
  type    = number
  default = 1234
}

variable "lmstudio_host_ip" {
  type    = string
  default = "127.0.0.1"
}

variable "metallb_start" {
  type    = string
  default = ""
}

variable "metallb_end" {
  type    = string
  default = ""
}
