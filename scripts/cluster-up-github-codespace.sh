#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_DIR="${ROOT_DIR}/.kube/generated"
KUBECONFIG_PATH="${KUBECONFIG_DIR}/current.yaml"
K3D_CONFIG_PATH="${ROOT_DIR}/.generated/k3d/github-codespace.yaml"

CLUSTER_NAME="${WORKSPACE_CLUSTER_NAME:-agentic-native-platform}"

command -v docker >/dev/null 2>&1 || { echo "docker is required"; exit 1; }
command -v k3d >/dev/null 2>&1 || { echo "k3d is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

mkdir -p "${KUBECONFIG_DIR}"
test -f "${K3D_CONFIG_PATH}" || {
  echo "Missing generated k3d config: ${K3D_CONFIG_PATH}" >&2
  echo "Run 'make terraform-apply TOPOLOGY=github-codespace TF_BIN=\${TF_BIN:-tofu}' first." >&2
  exit 1
}

if ! k3d kubeconfig get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  k3d cluster create --config "${K3D_CONFIG_PATH}"
else
  echo "k3d cluster '${CLUSTER_NAME}' already exists"
fi

k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"
kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes -o wide

echo "Workspace kubeconfig written to ${KUBECONFIG_PATH}"
