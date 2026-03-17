#!/usr/bin/env bash
set -euo pipefail
ENV=${ENV:-dev}
if ! command -v sops >/dev/null 2>&1; then
  echo "sops is not installed. Run make tools-install-local or install it manually." >&2
  exit 1
fi
for f in flux/secrets/${ENV}/*.plaintext.yaml; do
  [ -e "$f" ] || continue
  out="${f/.plaintext.yaml/.sops.yaml}"
  cp "$f" "$out"
  sops --encrypt --in-place "$out"
  echo "Encrypted $out"
done
