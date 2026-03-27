#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENV:-dev}"
OUT_DIR="${ROOT_DIR}/.generated/secrets/${ENVIRONMENT}"
NAMESPACE_SOURCE="${ROOT_DIR}/secrets/common/namespaces.yaml"
mkdir -p "${OUT_DIR}"

generate_secret() {
  openssl rand -hex 24
}

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi
: "${GOOGLE_API_KEY:=replace-me}"
: "${OPENAI_API_KEY:=}"
: "${ANTHROPIC_API_KEY:=}"
: "${AWS_ACCESS_KEY_ID:=}"
: "${AWS_SECRET_ACCESS_KEY:=}"
: "${AWS_SESSION_TOKEN:=}"
: "${AWS_REGION:=eu-central-1}"
: "${VERTEX_PROJECT_ID:=}"
: "${VERTEX_LOCATION:=europe-west3}"
: "${VERTEX_AI_API_KEY:=}"
: "${VERTEX_SERVICE_ACCOUNT_JSON_B64:=}"
: "${FINNHUB_API_TOKEN:=}"
: "${LITELLM_MASTER_KEY:=$(generate_secret)}"
: "${PLATFORM_POSTGRES_PASSWORD:=$(generate_secret)}"
: "${GRAFANA_ADMIN_USERNAME:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=$(generate_secret)}"
: "${GRAFANA_SERVICE_ACCOUNT_TOKEN:=}"
: "${GRAFANA_API_KEY:=}"

cp "${NAMESPACE_SOURCE}" "${OUT_DIR}/namespaces.yaml"
cat > "${OUT_DIR}/litellm-provider-secrets.yaml" <<EOF
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
  AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN}
  VERTEX_PROJECT_ID: ${VERTEX_PROJECT_ID}
  VERTEX_LOCATION: ${VERTEX_LOCATION}
  VERTEX_AI_API_KEY: ${VERTEX_AI_API_KEY}
  VERTEX_SERVICE_ACCOUNT_JSON_B64: ${VERTEX_SERVICE_ACCOUNT_JSON_B64}
EOF
cat > "${OUT_DIR}/kagent-agentgateway.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kagent-agentgateway
  namespace: kagent
type: Opaque
stringData:
  OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
EOF
cat > "${OUT_DIR}/finnhub-mcp-server.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: finnhub-mcp-server
  namespace: kagent
type: Opaque
stringData:
  FINNHUB_API_TOKEN: ${FINNHUB_API_TOKEN}
EOF
cat > "${OUT_DIR}/platform-postgres-auth.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: platform-postgres-auth
  namespace: context
type: Opaque
stringData:
  postgres-password: ${PLATFORM_POSTGRES_PASSWORD}
  password: ${PLATFORM_POSTGRES_PASSWORD}
EOF
cat > "${OUT_DIR}/observability-grafana-admin.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: observability-grafana-admin
  namespace: observability
type: Opaque
stringData:
  admin-user: ${GRAFANA_ADMIN_USERNAME}
  admin-password: ${GRAFANA_ADMIN_PASSWORD}
  GRAFANA_USERNAME: ${GRAFANA_ADMIN_USERNAME}
  GRAFANA_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
EOF
cat > "${OUT_DIR}/kagent-grafana-mcp.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: kagent-grafana-mcp
  namespace: kagent
type: Opaque
stringData:
EOF
if [[ -n "${GRAFANA_SERVICE_ACCOUNT_TOKEN}" ]]; then
  cat >> "${OUT_DIR}/kagent-grafana-mcp.yaml" <<EOF
  GRAFANA_SERVICE_ACCOUNT_TOKEN: ${GRAFANA_SERVICE_ACCOUNT_TOKEN}
EOF
elif [[ -n "${GRAFANA_API_KEY}" ]]; then
  cat >> "${OUT_DIR}/kagent-grafana-mcp.yaml" <<EOF
  GRAFANA_API_KEY: ${GRAFANA_API_KEY}
EOF
fi
rm -f "${OUT_DIR}/cluster-user-auth.yaml"
cat > "${OUT_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespaces.yaml
  - litellm-provider-secrets.yaml
  - kagent-agentgateway.yaml
  - finnhub-mcp-server.yaml
  - platform-postgres-auth.yaml
  - observability-grafana-admin.yaml
  - kagent-grafana-mcp.yaml
EOF

echo "Rendered plaintext secrets into ${OUT_DIR}"
if [[ -z "${GRAFANA_SERVICE_ACCOUNT_TOKEN}" && -z "${GRAFANA_API_KEY}" ]]; then
  echo "Grafana MCP credentials were not set. Rendered an empty Secret/kagent-grafana-mcp; provision a live token after Grafana is up." >&2
fi
