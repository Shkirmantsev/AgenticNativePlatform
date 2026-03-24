#!/usr/bin/env bash
set -euo pipefail
ENVIRONMENT="${ENV:-dev}"
TOPOLOGY_NAME="${TOPOLOGY:-local}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/secrets/${TOPOLOGY_NAME}"
OUT_DIR="${ROOT_DIR}/.generated/decrypted/${ENVIRONMENT}"
mkdir -p "${OUT_DIR}"
if ! command -v sops >/dev/null 2>&1; then
  echo "sops is not installed." >&2
  exit 1
fi
for f in "${SRC_DIR}"/*.sops.yaml; do
  [ -e "$f" ] || continue
  sops --decrypt "$f" > "${OUT_DIR}/$(basename "${f/.sops.yaml/.yaml}")"
  echo "Decrypted ${f} -> ${OUT_DIR}"
done
