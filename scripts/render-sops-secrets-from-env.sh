#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${ENV:-dev}"
OUT_DIR="${ROOT_DIR}/.generated/secrets/${ENVIRONMENT}"
mkdir -p "${OUT_DIR}"
ENV="${ENVIRONMENT}" "${ROOT_DIR}/scripts/render-plaintext-secrets.sh"
find "${OUT_DIR}" -maxdepth 1 -type f -name '*.yaml' \
  ! -name 'namespaces.yaml' \
  ! -name 'kustomization.yaml' \
  ! -name '*.plaintext.yaml' \
  | while read -r file; do
      cp "$file" "${file%.yaml}.plaintext.yaml"
    done
find "${OUT_DIR}" -maxdepth 1 -type f -name '*.yaml' \
  ! -name '*.plaintext.yaml' \
  ! -name 'namespaces.yaml' \
  ! -name 'kustomization.yaml' \
  -delete
echo "Rendered plaintext SOPS inputs into ${OUT_DIR}"
