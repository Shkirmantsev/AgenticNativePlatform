#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-}"
REQUEST_TIMEOUT="${KUBE_API_REQUEST_TIMEOUT:-10s}"

if [[ -z "${KUBECONFIG_PATH}" ]]; then
  echo "KUBECONFIG is not set." >&2
  exit 1
fi

if ! output="$(
  kubectl --kubeconfig "${KUBECONFIG_PATH}" --request-timeout="${REQUEST_TIMEOUT}" \
    get --raw='/readyz?verbose' 2>&1
)"; then
  echo "Kubernetes API server is unreachable or not ready for ${1:-this operation}." >&2
  if [[ -n "${output}" ]]; then
    echo "${output}" >&2
  fi
  exit 1
fi
