#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${ENV:-dev}"
TOPOLOGY_NAME="${TOPOLOGY:-local}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/.generated/secrets/${ENVIRONMENT}"
OUT_DIR="${ROOT_DIR}/secrets/${TOPOLOGY_NAME}"
mkdir -p "${OUT_DIR}"
if ! command -v sops >/dev/null 2>&1; then
  echo "sops is not installed. Run make tools-install-local or install it manually." >&2
  exit 1
fi
resources=()
for f in "${SRC_DIR}"/*.plaintext.yaml; do
  [ -e "$f" ] || continue
  out="${OUT_DIR}/$(basename "${f/.plaintext.yaml/.sops.yaml}")"
  cp "$f" "$out"
  sops --encrypt --in-place "$out"
  resources+=("  - $(basename "$out")")
  echo "Encrypted $out"
done
cat > "${OUT_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
$(printf '%s
' "${resources[@]}")
EOF
