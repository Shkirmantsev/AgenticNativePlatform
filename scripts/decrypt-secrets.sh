#!/usr/bin/env bash
set -euo pipefail
ENV=${ENV:-dev}
if ! command -v sops >/dev/null 2>&1; then
  echo "sops is not installed." >&2
  exit 1
fi
for f in flux/secrets/${ENV}/*.sops.yaml; do
  [ -e "$f" ] || continue
  sops --decrypt "$f"
done
