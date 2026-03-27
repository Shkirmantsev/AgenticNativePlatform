#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

ENVIRONMENT="${ENV:-dev}"
KUBECONFIG_PATH="${KUBECONFIG:-${ROOT_DIR}/.kube/generated/current.yaml}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
CURL_BIN="${CURL_BIN:-curl}"
JQ_BIN="${JQ_BIN:-jq}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-observability}"
GRAFANA_DEPLOYMENT="${GRAFANA_DEPLOYMENT:-observability-kube-prometheus-stack-grafana}"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-observability-kube-prometheus-stack-grafana}"
GRAFANA_SECRET="${GRAFANA_SECRET:-observability-grafana-admin}"
GRAFANA_LOCAL_PORT="${GRAFANA_BOOTSTRAP_LOCAL_PORT:-13000}"
GRAFANA_MCP_SERVICE_ACCOUNT="${GRAFANA_MCP_SERVICE_ACCOUNT:-kagent-grafana-mcp}"
GRAFANA_MCP_SECRET="${GRAFANA_MCP_SECRET:-kagent-grafana-mcp}"
GRAFANA_MCP_DEPLOYMENT="${GRAFANA_MCP_DEPLOYMENT:-kagent-kagent-grafana-mcp}"
KAGENT_NAMESPACE="${KAGENT_NAMESPACE:-kagent}"
KAGENT_HELMRELEASE_NAMESPACE="${KAGENT_HELMRELEASE_NAMESPACE:-flux-system}"
KAGENT_HELMRELEASE_NAME="${KAGENT_HELMRELEASE_NAME:-kagent}"
ROLL_TIMEOUT="${GRAFANA_MCP_ROLL_TIMEOUT:-5m}"
PF_LOG="$(mktemp)"
PF_PID=""

cleanup() {
  if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
  rm -f "${PF_LOG}"
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd "${KUBECTL_BIN}"
require_cmd "${CURL_BIN}"
require_cmd "${JQ_BIN}"

decode_secret_key() {
  local namespace="$1"
  local secret="$2"
  local key="$3"
  "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${namespace}" get secret "${secret}" -o json | "${JQ_BIN}" -r --arg key "${key}" '.data[$key] // empty' | base64 -d
}

if [[ -z "${GRAFANA_ADMIN_USERNAME:-}" ]]; then
  GRAFANA_ADMIN_USERNAME="$(decode_secret_key "${GRAFANA_NAMESPACE}" "${GRAFANA_SECRET}" "admin-user")"
fi
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  GRAFANA_ADMIN_PASSWORD="$(decode_secret_key "${GRAFANA_NAMESPACE}" "${GRAFANA_SECRET}" "admin-password")"
fi

if [[ -z "${GRAFANA_ADMIN_USERNAME:-}" || -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  echo "Grafana admin credentials are required via .env or Secret/${GRAFANA_SECRET} in namespace ${GRAFANA_NAMESPACE}." >&2
  exit 1
fi

echo "Waiting for Grafana deployment ${GRAFANA_NAMESPACE}/${GRAFANA_DEPLOYMENT}..."
"${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${GRAFANA_NAMESPACE}" rollout status "deployment/${GRAFANA_DEPLOYMENT}" --timeout="${ROLL_TIMEOUT}"

echo "Opening temporary Grafana port-forward on localhost:${GRAFANA_LOCAL_PORT}..."
"${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${GRAFANA_NAMESPACE}" port-forward "svc/${GRAFANA_SERVICE}" "${GRAFANA_LOCAL_PORT}:80" >"${PF_LOG}" 2>&1 &
PF_PID=$!

for _ in $(seq 1 60); do
  if "${CURL_BIN}" -fsS "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${PF_PID}" 2>/dev/null; then
    cat "${PF_LOG}" >&2
    echo "Grafana port-forward exited before becoming ready." >&2
    exit 1
  fi
  sleep 1
done

if ! "${CURL_BIN}" -fsS "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/health" >/dev/null 2>&1; then
  cat "${PF_LOG}" >&2
  echo "Timed out waiting for Grafana API on localhost:${GRAFANA_LOCAL_PORT}." >&2
  exit 1
fi

search_json="$("${CURL_BIN}" -fsS -u "${GRAFANA_ADMIN_USERNAME}:${GRAFANA_ADMIN_PASSWORD}" "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/serviceaccounts/search?perpage=1000")"
sa_id="$(printf '%s' "${search_json}" | "${JQ_BIN}" -r --arg name "${GRAFANA_MCP_SERVICE_ACCOUNT}" '.serviceAccounts[]? | select(.name==$name) | .id' | head -n1)"
if [[ -z "${sa_id}" ]]; then
  sa_id="$("${CURL_BIN}" -fsS -u "${GRAFANA_ADMIN_USERNAME}:${GRAFANA_ADMIN_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${GRAFANA_MCP_SERVICE_ACCOUNT}\",\"role\":\"Admin\",\"isDisabled\":false}" \
    "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/serviceaccounts" | "${JQ_BIN}" -r '.id')"
fi

if [[ -z "${sa_id}" || "${sa_id}" == "null" ]]; then
  echo "Failed to resolve Grafana service account ${GRAFANA_MCP_SERVICE_ACCOUNT}." >&2
  exit 1
fi

token="$("${CURL_BIN}" -fsS -u "${GRAFANA_ADMIN_USERNAME}:${GRAFANA_ADMIN_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"${GRAFANA_MCP_SERVICE_ACCOUNT}-$(date +%s)\",\"secondsToLive\":0}" \
  "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/serviceaccounts/${sa_id}/tokens" | "${JQ_BIN}" -r '.key')"

if [[ -z "${token}" || "${token}" == "null" ]]; then
  echo "Failed to create Grafana service account token." >&2
  exit 1
fi

OUT_DIR="${ROOT_DIR}/.generated/secrets/${ENVIRONMENT}"
mkdir -p "${OUT_DIR}"
cat > "${OUT_DIR}/${GRAFANA_MCP_SECRET}.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${GRAFANA_MCP_SECRET}
  namespace: ${KAGENT_NAMESPACE}
type: Opaque
stringData:
  GRAFANA_SERVICE_ACCOUNT_TOKEN: ${token}
EOF

if [[ -f "${ROOT_DIR}/.env" ]]; then
  tmpfile="$(mktemp)"
  awk -v token="${token}" '
    BEGIN { updated = 0 }
    /^GRAFANA_SERVICE_ACCOUNT_TOKEN=/ {
      print "GRAFANA_SERVICE_ACCOUNT_TOKEN=" token
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "GRAFANA_SERVICE_ACCOUNT_TOKEN=" token
      }
    }
  ' "${ROOT_DIR}/.env" > "${tmpfile}"
  mv "${tmpfile}" "${ROOT_DIR}/.env"
fi

echo "Applying Secret/${GRAFANA_MCP_SECRET} in namespace ${KAGENT_NAMESPACE}..."
"${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" apply -f "${OUT_DIR}/${GRAFANA_MCP_SECRET}.yaml"

if "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${KAGENT_NAMESPACE}" get deployment "${GRAFANA_MCP_DEPLOYMENT}" >/dev/null 2>&1; then
  echo "Restarting deployment ${KAGENT_NAMESPACE}/${GRAFANA_MCP_DEPLOYMENT}..."
  "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${KAGENT_NAMESPACE}" rollout restart "deployment/${GRAFANA_MCP_DEPLOYMENT}"
  "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${KAGENT_NAMESPACE}" rollout status "deployment/${GRAFANA_MCP_DEPLOYMENT}" --timeout="${ROLL_TIMEOUT}"
fi

if command -v flux >/dev/null 2>&1 && "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" -n "${KAGENT_HELMRELEASE_NAMESPACE}" get helmrelease "${KAGENT_HELMRELEASE_NAME}" >/dev/null 2>&1; then
  echo "Reconciling HelmRelease ${KAGENT_HELMRELEASE_NAMESPACE}/${KAGENT_HELMRELEASE_NAME}..."
  flux --kubeconfig "${KUBECONFIG_PATH}" reconcile helmrelease "${KAGENT_HELMRELEASE_NAME}" -n "${KAGENT_HELMRELEASE_NAMESPACE}" >/dev/null
fi

echo "Grafana MCP token provisioned and applied."
