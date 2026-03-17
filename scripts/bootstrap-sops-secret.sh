#!/usr/bin/env bash
set -euo pipefail
KEY_FILE=".sops/age.agekey"
if [[ ! -f "${KEY_FILE}" ]]; then
  echo "${KEY_FILE} not found. Run make sops-age-key first." >&2
  exit 1
fi
kubectl -n flux-system create secret generic sops-age-keys   --from-file=identity.agekey="${KEY_FILE}"   --dry-run=client -o yaml | kubectl apply -f -
echo "Created or updated flux-system/sops-age-keys"
