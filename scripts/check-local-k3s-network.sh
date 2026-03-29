#!/usr/bin/env bash
set -euo pipefail

TOPOLOGY_NAME="${TOPOLOGY:-local}"
KUBECONFIG_PATH="${KUBECONFIG:-}"
REQUEST_TIMEOUT="${KUBE_API_REQUEST_TIMEOUT:-10s}"
ENV_NAME="${ENV:-dev}"
SECRETS_MODE_NAME="${SECRETS_MODE:-external}"
if [[ "${SECRETS_MODE_NAME}" == "sops" ]]; then
  secrets_recovery_target="sops-bootstrap-cluster"
else
  secrets_recovery_target="apply-plaintext-secrets"
fi

if [[ "${TOPOLOGY_NAME}" != "local" ]]; then
  exit 0
fi

if [[ -z "${KUBECONFIG_PATH}" || ! -f "${KUBECONFIG_PATH}" ]]; then
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1 || ! command -v ip >/dev/null 2>&1; then
  exit 0
fi

current_host_ip="$(
  ip route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
)"
if [[ -z "${current_host_ip}" ]]; then
  current_host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [[ -z "${current_host_ip}" ]]; then
  exit 0
fi

cluster_node_ip="$(
  kubectl --kubeconfig "${KUBECONFIG_PATH}" --request-timeout="${REQUEST_TIMEOUT}" \
    get node -o jsonpath='{range .items[*]}{range .status.addresses[*]}{.type}={.address}{"\n"}{end}{end}' 2>/dev/null \
      | awk -F= '$1 == "InternalIP" { print $2; exit }'
)"

if [[ -z "${cluster_node_ip}" ]]; then
  exit 0
fi

if [[ "${current_host_ip}" == "${cluster_node_ip}" ]]; then
  exit 0
fi

cat >&2 <<EOF
Local k3s node IP drift detected for ${1:-this operation}.

Current host IP:    ${current_host_ip}
Cluster node IP:    ${cluster_node_ip}

Why this blocks recovery:
- the local control-plane was installed on one host IP and the workstation now owns another
- cluster-internal API traffic may still target the stale node IP
- Flux, cert-manager, KServe, Istio ambient/CNI, MetalLB, and observability controllers cannot repair themselves once that API path is broken

Recommended recovery:
1. make repair-local-k3s-network TOPOLOGY=local
2. make run-cluster-from-scratch TOPOLOGY=local ENV=${ENV_NAME} SECRETS_MODE=${SECRETS_MODE_NAME}

If you only need the cluster runtime back and will bootstrap GitOps separately:
1. make repair-local-k3s-network TOPOLOGY=local
2. make install-flux-local TOPOLOGY=local
3. make ${secrets_recovery_target} TOPOLOGY=local ENV=${ENV_NAME}
4. make bootstrap-flux-instance TOPOLOGY=local ENV=${ENV_NAME}
5. make reconcile
EOF

exit 1
