#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
RUNTIME="${RUNTIME:-none}"
SECRETS_MODE="${SECRETS_MODE:-external}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-false}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
if [[ -z "${GIT_REPO_URL}" && -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi
: "${GIT_REPO_URL:?Set GIT_REPO_URL in the environment or .env}"
TOPOLOGY="$TOPOLOGY" ENV="$ENVIRONMENT" RUNTIME="$RUNTIME" SECRETS_MODE="$SECRETS_MODE" LMSTUDIO_ENABLED="$LMSTUDIO_ENABLED" ./scripts/render-cluster-kustomization.sh
./scripts/render-flux-values.sh "$TOPOLOGY"
CLUSTER_PATH="./flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"
DECRYPTION_BLOCK=""
if [[ "${SECRETS_MODE}" == "sops" ]]; then
  DECRYPTION_BLOCK=$(cat <<'EOF'
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF
)
fi
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: platform
  namespace: flux-system
spec:
  interval: 1m
  url: ${GIT_REPO_URL}
  ref:
    branch: ${GIT_BRANCH}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: platform
  path: ${CLUSTER_PATH}
${DECRYPTION_BLOCK}
EOF
echo "Flux Git source bootstrapped for ${CLUSTER_PATH} (LMSTUDIO_ENABLED=${LMSTUDIO_ENABLED}, SECRETS_MODE=${SECRETS_MODE})"
