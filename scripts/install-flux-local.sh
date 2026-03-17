#!/usr/bin/env bash
set -euo pipefail
if ! command -v flux >/dev/null 2>&1; then
  echo "flux CLI is not installed" >&2
  exit 1
fi
kubectl get ns flux-system >/dev/null 2>&1 || kubectl create ns flux-system
flux install --namespace flux-system
