#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_DIR="${ROOT_DIR}/.kube/generated"
KUBECONFIG_PATH="${KUBECONFIG_DIR}/current.yaml"

CLUSTER_NAME="${WORKSPACE_CLUSTER_NAME:-agentic-native-platform}"
K3S_VERSION="${K3S_VERSION:-v1.34.5+k3s1}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:${K3S_VERSION/+/-}}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"

command -v docker >/dev/null 2>&1 || { echo "docker is required"; exit 1; }
command -v k3d >/dev/null 2>&1 || { echo "k3d is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

mkdir -p "${KUBECONFIG_DIR}"

if ! k3d kubeconfig get "${CLUSTER_NAME}" >/dev/null 2>&1; then
  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 0 \
    --image "${K3S_IMAGE}" \
    --wait \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=servicelb@server:0" \
    --k3s-arg "--cluster-domain=${CLUSTER_DOMAIN}@server:0" \
    --k3s-arg "--secrets-encryption@server:0" \
    --k3s-node-label "topology-role=control-plane@server:0"
else
  echo "k3d cluster '${CLUSTER_NAME}' already exists"
fi

k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"
kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes -o wide

echo "Workspace kubeconfig written to ${KUBECONFIG_PATH}"
