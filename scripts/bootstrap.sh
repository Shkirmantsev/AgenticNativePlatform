#!/usr/bin/env bash
set -euo pipefail

# Install additional CLIs used by the project.
install_if_missing() {
  local name="$1"
  local check_cmd="$2"
  local install_cmd="$3"

  if eval "$check_cmd" >/dev/null 2>&1; then
    echo "[ok] ${name} already installed"
  else
    echo "[install] ${name}"
    eval "$install_cmd"
  fi
}

install_if_missing "kind" "command -v kind" "curl -fsSL https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 -o /tmp/kind && chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind"
install_if_missing "k3d" "command -v k3d" "curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
install_if_missing "kustomize" "command -v kustomize" "curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash && sudo mv kustomize /usr/local/bin/kustomize"
install_if_missing "flux" "command -v flux" "curl -s https://fluxcd.io/install.sh | sudo bash"

printf '\nEnvironment preflight:\n'
bash scripts/validate-environment.sh
