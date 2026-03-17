#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENV:-dev}"
OUT_DIR="${ROOT_DIR}/flux/secrets/${ENVIRONMENT}"
mkdir -p "${OUT_DIR}"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi
: "${GOOGLE_API_KEY:=replace-me}"
: "${OPENAI_API_KEY:=}"
: "${ANTHROPIC_API_KEY:=}"
: "${AWS_ACCESS_KEY_ID:=}"
: "${AWS_SECRET_ACCESS_KEY:=}"
: "${AWS_REGION:=eu-central-1}"
: "${VERTEX_PROJECT_ID:=}"
: "${VERTEX_LOCATION:=europe-west3}"
: "${VERTEX_SERVICE_ACCOUNT_JSON_B64:=}"
: "${LITELLM_MASTER_KEY:=change-me}"
cat > "${OUT_DIR}/litellm-provider-secrets.plaintext.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: litellm-provider-secrets
  namespace: ai-gateway
type: Opaque
stringData:
  LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
  GOOGLE_API_KEY: ${GOOGLE_API_KEY}
  OPENAI_API_KEY: ${OPENAI_API_KEY}
  ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
  AWS_REGION: ${AWS_REGION}
  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
  VERTEX_PROJECT_ID: ${VERTEX_PROJECT_ID}
  VERTEX_LOCATION: ${VERTEX_LOCATION}
  VERTEX_SERVICE_ACCOUNT_JSON_B64: ${VERTEX_SERVICE_ACCOUNT_JSON_B64}
EOF
cat > "${OUT_DIR}/kagent-agentgateway.plaintext.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kagent-agentgateway
  namespace: kagent
type: Opaque
stringData:
  OPENAI_API_KEY: dummy
EOF
echo "Rendered plaintext SOPS inputs into ${OUT_DIR}"
