#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
RUNTIME="${RUNTIME:-none}"
SECRETS_MODE="${SECRETS_MODE:-external}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-false}"
OUT_DIR="flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"

case "${RUNTIME}" in
  none|ollama|vllm) ;;
  *)
    echo "Unsupported runtime: ${RUNTIME}" >&2
    exit 1
    ;;
esac

case "${SECRETS_MODE}" in
  external|sops) ;;
  *)
    echo "Unsupported secrets mode: ${SECRETS_MODE}" >&2
    exit 1
    ;;
esac

case "${LMSTUDIO_ENABLED}" in
  true|false) ;;
  *)
    echo "LMSTUDIO_ENABLED must be 'true' or 'false', got: ${LMSTUDIO_ENABLED}" >&2
    exit 1
    ;;
esac

mkdir -p "${OUT_DIR}"
{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../components/platform-core
  - ../../../generated/${TOPOLOGY}
  - ../../../components/platform-runtime-${RUNTIME}
EOF
if [[ "${LMSTUDIO_ENABLED}" == "true" ]]; then
  echo '  - ../../../components/platform-lmstudio'
fi
if [[ "${SECRETS_MODE}" == "sops" ]]; then
  echo '  - ../../../secrets/'"${ENVIRONMENT}"
fi
cat <<EOF
  - ../../../overlays/${ENVIRONMENT}
EOF
} > "${OUT_DIR}/kustomization.yaml"
echo "Rendered ${OUT_DIR}/kustomization.yaml"
