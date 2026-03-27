#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${ROOT_DIR}/.kube/generated/current.yaml"
CLUSTER_NAME="${WORKSPACE_CLUSTER_NAME:-agentic-native-platform}"

if command -v k3d >/dev/null 2>&1 && k3d kubeconfig get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  k3d cluster delete "${CLUSTER_NAME}"
else
  echo "k3d cluster '${CLUSTER_NAME}' does not exist"
fi

rm -f "${KUBECONFIG_PATH}"
