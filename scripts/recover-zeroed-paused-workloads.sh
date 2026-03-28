#!/usr/bin/env bash
set -euo pipefail

PAUSE_NAMESPACES="${PAUSE_NAMESPACES:-${STOP_NAMESPACES:-}}"

./scripts/require-kube-apiserver.sh "recovering zeroed paused workloads"

if [[ -z "${PAUSE_NAMESPACES}" ]]; then
  echo "PAUSE_NAMESPACES is empty; nothing to recover." >&2
  exit 0
fi

recovered=0
for namespace in ${PAUSE_NAMESPACES}; do
  kubectl get namespace "${namespace}" >/dev/null 2>&1 || continue
  for resource in deployment statefulset; do
    zero_names="$(
      kubectl -n "${namespace}" get "${resource}" \
        -o jsonpath='{range .items[?(@.spec.replicas==0)]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
    )"
    [[ -n "${zero_names}" ]] || continue
    for name in ${zero_names}; do
      echo "Recovering ${resource}/${namespace}/${name} -> 1"
      kubectl -n "${namespace}" scale "${resource}/${name}" --replicas=1
      recovered=$((recovered + 1))
    done
  done
done

echo "Recovered ${recovered} zero-replica paused workloads to 1 replica."
