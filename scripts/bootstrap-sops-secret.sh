#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${ROOT_DIR}/.sops/age.agekey"
[[ -f "${KEY_FILE}" ]] || { echo "Missing ${KEY_FILE}. Run make sops-age-key first." >&2; exit 1; }
kubectl -n flux-system create secret generic sops-age --from-file=age.agekey="${KEY_FILE}" --dry-run=client -o yaml | kubectl apply -f -
echo "Applied flux-system/sops-age"
