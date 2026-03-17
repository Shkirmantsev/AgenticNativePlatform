#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
RUNTIME="${RUNTIME:-none}"
SECRETS_MODE="${SECRETS_MODE:-external}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-false}"
OUT_DIR="flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"
mkdir -p "${OUT_DIR}"
{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../components/platform-core
  - ../../../generated/${TOPOLOGY}/litellm-values-configmap.yaml
  - ../../../generated/${TOPOLOGY}/tei-values-configmap.yaml
  - ../../../generated/${TOPOLOGY}/metallb-values.yaml
  - ../../../components/platform-runtime-${RUNTIME}
EOF
if [[ "${RUNTIME}" == "ollama" ]]; then
  echo '  - ../../../generated/'"${TOPOLOGY}"'/ollama-values-configmap.yaml'
fi
if [[ "${RUNTIME}" == "vllm" ]]; then
  echo '  - ../../../generated/'"${TOPOLOGY}"'/vllm-values-configmap.yaml'
fi
if [[ "${LMSTUDIO_ENABLED}" == "true" ]]; then
  echo '  - ../../../generated/'"${TOPOLOGY}"'/lmstudio-values-configmap.yaml'
  echo '  - ../../../components/platform-lmstudio'
fi
if [[ "${SECRETS_MODE}" == "sops" ]]; then
  echo '  - ../../../secrets/'"${ENVIRONMENT}"
elif [[ "${SECRETS_MODE}" == "plaintext" ]]; then
  echo '  - ../../../generated/secrets/'"${ENVIRONMENT}"
fi
cat <<EOF
  - ../../../overlays/${ENVIRONMENT}
EOF
} > "${OUT_DIR}/kustomization.yaml"
echo "Rendered ${OUT_DIR}/kustomization.yaml"
