#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENV:-dev}"
OUT_DIR="${ROOT_DIR}/.generated/secrets/${ENVIRONMENT}"
mkdir -p "${OUT_DIR}"
ENV="${ENVIRONMENT}" "${ROOT_DIR}/scripts/render-plaintext-secrets.sh"
# Normalize file names for the SOPS pipeline
cp "${OUT_DIR}/litellm-provider-secrets.yaml" "${OUT_DIR}/litellm-provider-secrets.plaintext.yaml"
cp "${OUT_DIR}/kagent-agentgateway.yaml" "${OUT_DIR}/kagent-agentgateway.plaintext.yaml"
cp "${OUT_DIR}/kagent-grafana-mcp.yaml" "${OUT_DIR}/kagent-grafana-mcp.plaintext.yaml"
cp "${OUT_DIR}/platform-postgres-auth.yaml" "${OUT_DIR}/platform-postgres-auth.plaintext.yaml"
cp "${OUT_DIR}/observability-grafana-admin.yaml" "${OUT_DIR}/observability-grafana-admin.plaintext.yaml"
if [[ -f "${OUT_DIR}/cluster-user-auth.yaml" ]]; then
  cp "${OUT_DIR}/cluster-user-auth.yaml" "${OUT_DIR}/cluster-user-auth.plaintext.yaml"
fi
rm -f \
  "${OUT_DIR}/litellm-provider-secrets.yaml" \
  "${OUT_DIR}/kagent-agentgateway.yaml" \
  "${OUT_DIR}/kagent-grafana-mcp.yaml" \
  "${OUT_DIR}/platform-postgres-auth.yaml" \
  "${OUT_DIR}/observability-grafana-admin.yaml" \
  "${OUT_DIR}/cluster-user-auth.yaml" \
  "${OUT_DIR}/namespaces.yaml" \
  "${OUT_DIR}/kustomization.yaml"
echo "Rendered plaintext SOPS inputs into ${OUT_DIR}"
