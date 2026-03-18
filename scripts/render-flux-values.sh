#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${1:-${TOPOLOGY:-local}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN_DIR="${ROOT_DIR}/flux/generated/${TOPOLOGY}"
mkdir -p "${GEN_DIR}"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-flash-lite-preview}"
LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"
LMSTUDIO_CHAT_MODEL="${LMSTUDIO_CHAT_MODEL:-qwen/qwen3-4b}"
LMSTUDIO_EMBEDDING_MODEL="${LMSTUDIO_EMBEDDING_MODEL:-text-embedding-qwen3-embedding-0.6b}"
OLLAMA_VERSION="${OLLAMA_VERSION:-v0.18.0}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b-instruct}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-onnx-models/all-MiniLM-L6-v2-onnx}"
VLLM_MODEL="${VLLM_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-2}"
VLLM_CPU_NUM_OF_RESERVED_CPU="${VLLM_CPU_NUM_OF_RESERVED_CPU:-1}"
VLLM_LD_PRELOAD="${VLLM_LD_PRELOAD:-}"
VLLM_IMAGE="${VLLM_IMAGE:-public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest}"
ECHO_MCP_IMAGE="${ECHO_MCP_IMAGE:-ghcr.io/example/echo-mcp:0.1.0}"

cat > "${GEN_DIR}/litellm-values-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-values
  namespace: flux-system
data:
  values.yaml: |
    config: |
      general_settings:
        master_key: os.environ/LITELLM_MASTER_KEY
        store_model_in_db: false
        infer_model_from_keys: true
      litellm_settings:
        set_verbose: false
      model_list:
        - model_name: default-gemini
          litellm_params:
            model: gemini/${GEMINI_MODEL}
            api_key: os.environ/GOOGLE_API_KEY
        - model_name: openai-default
          litellm_params:
            model: openai/gpt-4o-mini
            api_key: os.environ/OPENAI_API_KEY
        - model_name: anthropic-default
          litellm_params:
            model: anthropic/claude-3-5-haiku-latest
            api_key: os.environ/ANTHROPIC_API_KEY
        - model_name: vertex-gemini
          litellm_params:
            model: vertex_ai/gemini-2.5-flash
            vertex_project: os.environ/VERTEX_PROJECT_ID
            vertex_location: os.environ/VERTEX_LOCATION
        - model_name: bedrock-claude
          litellm_params:
            model: bedrock/anthropic.claude-3-5-haiku-20241022-v1:0
            aws_region_name: os.environ/AWS_REGION
        - model_name: local-lmstudio
          litellm_params:
            model: openai/${LMSTUDIO_CHAT_MODEL}
            api_base: http://lmstudio-external.ai-gateway.svc.cluster.local:${LMSTUDIO_PORT}/v1
            api_key: dummy
        - model_name: local-lmstudio-embeddings
          litellm_params:
            model: openai/${LMSTUDIO_EMBEDDING_MODEL}
            api_base: http://lmstudio-external.ai-gateway.svc.cluster.local:${LMSTUDIO_PORT}/v1
            api_key: dummy
        - model_name: local-ollama
          litellm_params:
            model: ollama/${OLLAMA_DEFAULT_MODEL}
            api_base: http://ollama.ai-models.svc.cluster.local:11434
        - model_name: local-vllm
          litellm_params:
            model: openai/local-vllm
            api_base: http://vllm-openai.ai-models.svc.cluster.local:8000/v1
            api_key: dummy
EOF

cat > "${GEN_DIR}/tei-values-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: tei-values
  namespace: flux-system
data:
  values.yaml: |
    model: ${EMBEDDING_MODEL}
EOF

cat > "${GEN_DIR}/ollama-values-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ollama-values
  namespace: flux-system
data:
  values.yaml: |
    image:
      tag: ${OLLAMA_VERSION#v}
    modelPull:
      model: ${OLLAMA_DEFAULT_MODEL}
EOF

cat > "${GEN_DIR}/vllm-values-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: vllm-values
  namespace: flux-system
data:
  values.yaml: |
    image:
      repository: ${VLLM_IMAGE%:*}
      tag: ${VLLM_IMAGE##*:}
    model: ${VLLM_MODEL}
    env:
      VLLM_CPU_KVCACHE_SPACE: "${VLLM_CPU_KVCACHE_SPACE}"
      VLLM_CPU_NUM_OF_RESERVED_CPU: "${VLLM_CPU_NUM_OF_RESERVED_CPU}"
      VLLM_LD_PRELOAD: "${VLLM_LD_PRELOAD}"
EOF

cat > "${GEN_DIR}/echo-mcp-values-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: echo-mcp-values
  namespace: flux-system
data:
  image: ${ECHO_MCP_IMAGE}
EOF

resource_entries=()
for generated_file in \
  litellm-values-configmap.yaml \
  tei-values-configmap.yaml \
  ollama-values-configmap.yaml \
  vllm-values-configmap.yaml \
  echo-mcp-values-configmap.yaml \
  lmstudio-values-configmap.yaml \
  metallb-values.yaml \
  lmstudio-endpoint.yaml; do
  if [[ -f "${GEN_DIR}/${generated_file}" ]]; then
    resource_entries+=("  - ${generated_file}")
  fi
done

{
  cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOF
  printf '%s\n' "${resource_entries[@]}"
} > "${GEN_DIR}/kustomization.yaml"

echo "Rendered Flux values ConfigMaps into ${GEN_DIR}"
