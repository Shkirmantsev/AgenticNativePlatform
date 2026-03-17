#!/usr/bin/env bash
set -euo pipefail

TOPOLOGY="${1:-${TOPOLOGY:-local}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/environments/${TOPOLOGY}"
TF_VARS_FILE="${TF_DIR}/terraform.tfvars"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

LOCAL_HOST_IP="${LOCAL_HOST_IP:-192.168.1.108}"
LOCAL_SSH_USER="${LOCAL_SSH_USER:-dmytro}"
MINIPC_IP="${MINIPC_IP:-192.168.1.50}"
MINIPC_SSH_USER="${MINIPC_SSH_USER:-ubuntu}"
REMOTE_WORKER_IP="${REMOTE_WORKER_IP:-192.168.1.60}"
REMOTE_WORKER_SSH_USER="${REMOTE_WORKER_SSH_USER:-ubuntu}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-~/.ssh/id_ed25519}"
METALLB_START="${METALLB_START:-192.168.1.240}"
METALLB_END="${METALLB_END:-192.168.1.250}"
BASE_DOMAIN="${BASE_DOMAIN:-home.arpa}"
LMSTUDIO_HOST_IP="${LMSTUDIO_HOST_IP:-$LOCAL_HOST_IP}"
LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"

mkdir -p "${TF_DIR}"

case "${TOPOLOGY}" in
  local)
    cat > "${TF_VARS_FILE}" <<EOT
control_plane = {
  name         = "localhost"
  ansible_host = "127.0.0.1"
  ansible_user = "${LOCAL_SSH_USER}"
  connection   = "local"
  private_key  = ""
}
workers = []
metallb_start   = "${METALLB_START}"
metallb_end     = "${METALLB_END}"
base_domain     = "${BASE_DOMAIN}"
local_host_ip   = "${LOCAL_HOST_IP}"
lmstudio_host_ip = "${LMSTUDIO_HOST_IP}"
lmstudio_port   = ${LMSTUDIO_PORT}
EOT
    ;;
  minipc)
    cat > "${TF_VARS_FILE}" <<EOT
control_plane = {
  name         = "minipc"
  ansible_host = "${MINIPC_IP}"
  ansible_user = "${MINIPC_SSH_USER}"
  connection   = "ssh"
  private_key  = "${SSH_PRIVATE_KEY}"
}
workers = []
metallb_start   = "${METALLB_START}"
metallb_end     = "${METALLB_END}"
base_domain     = "${BASE_DOMAIN}"
local_host_ip   = "${LOCAL_HOST_IP}"
lmstudio_host_ip = "${LMSTUDIO_HOST_IP}"
lmstudio_port   = ${LMSTUDIO_PORT}
EOT
    ;;
  hybrid)
    cat > "${TF_VARS_FILE}" <<EOT
control_plane = {
  name         = "minipc"
  ansible_host = "${MINIPC_IP}"
  ansible_user = "${MINIPC_SSH_USER}"
  connection   = "ssh"
  private_key  = "${SSH_PRIVATE_KEY}"
}
workers = [
  {
    name         = "workstation"
    ansible_host = "${LOCAL_HOST_IP}"
    ansible_user = "${LOCAL_SSH_USER}"
    connection   = "local"
    private_key  = ""
  }
]
metallb_start   = "${METALLB_START}"
metallb_end     = "${METALLB_END}"
base_domain     = "${BASE_DOMAIN}"
local_host_ip   = "${LOCAL_HOST_IP}"
lmstudio_host_ip = "${LMSTUDIO_HOST_IP}"
lmstudio_port   = ${LMSTUDIO_PORT}
EOT
    ;;
  hybrid-remote)
    cat > "${TF_VARS_FILE}" <<EOT
control_plane = {
  name         = "minipc"
  ansible_host = "${MINIPC_IP}"
  ansible_user = "${MINIPC_SSH_USER}"
  connection   = "ssh"
  private_key  = "${SSH_PRIVATE_KEY}"
}
workers = [
  {
    name         = "workstation"
    ansible_host = "${LOCAL_HOST_IP}"
    ansible_user = "${LOCAL_SSH_USER}"
    connection   = "local"
    private_key  = ""
  },
  {
    name         = "remote-worker"
    ansible_host = "${REMOTE_WORKER_IP}"
    ansible_user = "${REMOTE_WORKER_SSH_USER}"
    connection   = "ssh"
    private_key  = "${SSH_PRIVATE_KEY}"
  }
]
metallb_start   = "${METALLB_START}"
metallb_end     = "${METALLB_END}"
base_domain     = "${BASE_DOMAIN}"
local_host_ip   = "${LOCAL_HOST_IP}"
lmstudio_host_ip = "${LMSTUDIO_HOST_IP}"
lmstudio_port   = ${LMSTUDIO_PORT}
EOT
    ;;
  *)
    echo "Unsupported topology: ${TOPOLOGY}" >&2
    exit 1
    ;;
esac

echo "Rendered ${TF_VARS_FILE}"
