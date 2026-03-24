#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOPOLOGY_NAME="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
SECRETS_MODE_VALUE="${SECRETS_MODE:-external}"
CLUSTER_ROOT="${ROOT_DIR}/clusters/${TOPOLOGY_NAME}-${ENVIRONMENT}"
SECRETS_FILE="${CLUSTER_ROOT}/secrets.yaml"

if [[ ! -d "${CLUSTER_ROOT}" ]]; then
  echo "Missing static cluster root: ${CLUSTER_ROOT}" >&2
  exit 1
fi

decryption_block=""
if [[ "${SECRETS_MODE_VALUE}" == "sops" ]]; then
  decryption_block=$'  decryption:\n    provider: sops\n    secretRef:\n      name: sops-age'
fi

cat > "${SECRETS_FILE}" <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-secrets
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 10m
  dependsOn:
    - name: platform-infrastructure
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/${TOPOLOGY_NAME}-${ENVIRONMENT}/secrets
${decryption_block}
EOF

echo "Rendered ${SECRETS_FILE} for SECRETS_MODE=${SECRETS_MODE_VALUE}"
