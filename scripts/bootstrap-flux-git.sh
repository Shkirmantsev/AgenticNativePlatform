#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
RUNTIME="${RUNTIME:-none}"
SECRETS_MODE="${SECRETS_MODE:-external}"
PLATFORM_PROFILE="${PLATFORM_PROFILE:-}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-false}"
PLATFORM_ROOT_TIMEOUT="${PLATFORM_ROOT_TIMEOUT:-60m}"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
if [[ -z "${GIT_REPO_URL}" && -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi
: "${GIT_REPO_URL:?Set GIT_REPO_URL in the environment or .env}"
TOPOLOGY="$TOPOLOGY" \
ENV="$ENVIRONMENT" \
RUNTIME="$RUNTIME" \
SECRETS_MODE="$SECRETS_MODE" \
PLATFORM_PROFILE="$PLATFORM_PROFILE" \
LMSTUDIO_ENABLED="$LMSTUDIO_ENABLED" \
PLATFORM_ROOT_TIMEOUT="$PLATFORM_ROOT_TIMEOUT" \
GIT_REPO_URL="$GIT_REPO_URL" \
GIT_BRANCH="$GIT_BRANCH" \
./scripts/render-cluster-kustomization.sh
CLUSTER_PATH="./flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"
BOOTSTRAP_PATH="${CLUSTER_PATH}/bootstrap-flux"
kubectl apply -k "${BOOTSTRAP_PATH}"
remote_line="$(git ls-remote --exit-code "${GIT_REPO_URL}" "refs/heads/${GIT_BRANCH}")"
remote_head="${remote_line%%$'\t'*}"
echo "Flux Git source bootstrapped from ${BOOTSTRAP_PATH} for ${CLUSTER_PATH} from ${GIT_REPO_URL}@${GIT_BRANCH} (${remote_head}) (PLATFORM_PROFILE=${PLATFORM_PROFILE:-auto}, LMSTUDIO_ENABLED=${LMSTUDIO_ENABLED}, SECRETS_MODE=${SECRETS_MODE})"
