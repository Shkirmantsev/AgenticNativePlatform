#!/usr/bin/env bash
set -euo pipefail

STATE_NAMESPACE="${STATE_NAMESPACE:-flux-system}"
STATE_CONFIGMAP="${PAUSE_STATE_CONFIGMAP:-cluster-pause-state}"
PAUSE_NAMESPACES="${PAUSE_NAMESPACES:-${STOP_NAMESPACES:-}}"

./scripts/require-kube-apiserver.sh "saving paused workload state"

if [[ -z "${PAUSE_NAMESPACES}" ]]; then
  echo "PAUSE_NAMESPACES is empty; nothing to snapshot." >&2
  exit 0
fi

tmp_file="$(mktemp)"
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

for namespace in ${PAUSE_NAMESPACES}; do
  if ! namespace_check="$(
    kubectl get namespace "${namespace}" -o name 2>&1
  )"; then
    if grep -qi 'not found' <<<"${namespace_check}"; then
      continue
    fi
    echo "Failed to query namespace/${namespace}: ${namespace_check}" >&2
    exit 1
  fi

  if ! deployment_rows="$(
    kubectl -n "${namespace}" get deployment \
    -o jsonpath='{range .items[*]}deployment{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' \
    2>&1
  )"; then
    echo "Failed to list deployments in namespace/${namespace}: ${deployment_rows}" >&2
    exit 1
  fi
  printf '%s' "${deployment_rows}" >>"${tmp_file}"

  if ! statefulset_rows="$(
    kubectl -n "${namespace}" get statefulset \
    -o jsonpath='{range .items[*]}statefulset{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' \
    2>&1
  )"; then
    echo "Failed to list statefulsets in namespace/${namespace}: ${statefulset_rows}" >&2
    exit 1
  fi
  printf '%s' "${statefulset_rows}" >>"${tmp_file}"
done

sort -u "${tmp_file}" -o "${tmp_file}"

kubectl -n "${STATE_NAMESPACE}" create configmap "${STATE_CONFIGMAP}" \
  --from-file=replicas.tsv="${tmp_file}" \
  --from-literal=namespaces="${PAUSE_NAMESPACES}" \
  --from-literal=savedAt="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Saved paused workload replica state to ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}."
