#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_TOPOLOGY="${TOPOLOGY-}"
ENVIRONMENT_INPUT="${ENV-}"
RUNTIME_INPUT="${RUNTIME-}"
SECRETS_MODE_INPUT="${SECRETS_MODE-}"
PLATFORM_PROFILE_INPUT="${PLATFORM_PROFILE-}"
LMSTUDIO_ENABLED_INPUT="${LMSTUDIO_ENABLED-}"
PLATFORM_BOOTSTRAP_TIMEOUT_INPUT="${PLATFORM_BOOTSTRAP_TIMEOUT-}"
PLATFORM_INFRA_TIMEOUT_INPUT="${PLATFORM_INFRA_TIMEOUT-}"
PLATFORM_APPS_TIMEOUT_INPUT="${PLATFORM_APPS_TIMEOUT-}"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

TOPOLOGY="${ENV_TOPOLOGY:-${TOPOLOGY:-local}}"
ENVIRONMENT="${ENVIRONMENT_INPUT:-${ENV:-dev}}"
RUNTIME="${RUNTIME_INPUT:-${RUNTIME:-none}}"
SECRETS_MODE="${SECRETS_MODE_INPUT:-${SECRETS_MODE:-external}}"
PLATFORM_PROFILE="${PLATFORM_PROFILE_INPUT:-${PLATFORM_PROFILE:-}}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED_INPUT:-${LMSTUDIO_ENABLED:-false}}"
PLATFORM_BOOTSTRAP_TIMEOUT="${PLATFORM_BOOTSTRAP_TIMEOUT_INPUT:-${PLATFORM_BOOTSTRAP_TIMEOUT:-10m}}"
PLATFORM_INFRA_TIMEOUT="${PLATFORM_INFRA_TIMEOUT_INPUT:-${PLATFORM_INFRA_TIMEOUT:-15m}}"
PLATFORM_APPS_TIMEOUT="${PLATFORM_APPS_TIMEOUT_INPUT:-${PLATFORM_APPS_TIMEOUT:-20m}}"
TF_BIN="${TF_BIN:-tofu}"
TF_DIR="${ROOT_DIR}/terraform/environments/${TOPOLOGY}"
VLLM_IMAGE="${VLLM_IMAGE:-public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest}"
VLLM_IMAGE_REPOSITORY="${VLLM_IMAGE%:*}"
VLLM_IMAGE_TAG="${VLLM_IMAGE##*:}"

"${ROOT_DIR}/scripts/render-terraform-tfvars.sh" "${TOPOLOGY}"
"${TF_BIN}" -chdir="${TF_DIR}" init -input=false >/dev/null
TF_VAR_environment="${ENVIRONMENT}" \
TF_VAR_runtime="${RUNTIME}" \
TF_VAR_secrets_mode="${SECRETS_MODE}" \
TF_VAR_platform_profile="${PLATFORM_PROFILE}" \
TF_VAR_lmstudio_enabled="${LMSTUDIO_ENABLED}" \
TF_VAR_platform_bootstrap_timeout="${PLATFORM_BOOTSTRAP_TIMEOUT}" \
TF_VAR_platform_infra_timeout="${PLATFORM_INFRA_TIMEOUT}" \
TF_VAR_platform_apps_timeout="${PLATFORM_APPS_TIMEOUT}" \
TF_VAR_gemini_model="${GEMINI_MODEL:-gemini-3.1-flash-lite-preview}" \
TF_VAR_lmstudio_chat_model="${LMSTUDIO_CHAT_MODEL:-qwen/qwen3-4b}" \
TF_VAR_lmstudio_embedding_model="${LMSTUDIO_EMBEDDING_MODEL:-text-embedding-qwen3-embedding-0.6b}" \
TF_VAR_embedding_model="${EMBEDDING_MODEL:-onnx-models/all-MiniLM-L6-v2-onnx}" \
TF_VAR_ollama_version="${OLLAMA_VERSION:-v0.18.0}" \
TF_VAR_ollama_default_model="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b-instruct}" \
TF_VAR_vllm_model="${VLLM_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}" \
TF_VAR_vllm_image_repository="${VLLM_IMAGE_REPOSITORY}" \
TF_VAR_vllm_image_tag="${VLLM_IMAGE_TAG}" \
TF_VAR_vllm_cpu_kvcache_space="${VLLM_CPU_KVCACHE_SPACE:-2}" \
TF_VAR_vllm_cpu_num_of_reserved_cpu="${VLLM_CPU_NUM_OF_RESERVED_CPU:-1}" \
TF_VAR_vllm_ld_preload="${VLLM_LD_PRELOAD:-}" \
TF_VAR_echo_mcp_image="${ECHO_MCP_IMAGE:-ghcr.io/example/echo-mcp:0.1.0}" \
TF_VAR_lmstudio_port="${LMSTUDIO_PORT:-1234}" \
"${TF_BIN}" -chdir="${TF_DIR}" apply -auto-approve -input=false -lock-timeout=60s

echo "Regenerated declarative cluster root for ${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE} (PLATFORM_PROFILE=${PLATFORM_PROFILE:-auto})"
