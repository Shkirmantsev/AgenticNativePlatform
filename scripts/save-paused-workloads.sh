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
existing_tmp_file="$(mktemp)"
cleanup() {
  rm -f "${tmp_file}"
  rm -f "${existing_tmp_file}"
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
  if [[ -n "${deployment_rows}" ]]; then
    printf '%s\n' "${deployment_rows}" >>"${tmp_file}"
  fi

  if ! statefulset_rows="$(
    kubectl -n "${namespace}" get statefulset \
    -o jsonpath='{range .items[*]}statefulset{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' \
    2>&1
  )"; then
    echo "Failed to list statefulsets in namespace/${namespace}: ${statefulset_rows}" >&2
    exit 1
  fi
  if [[ -n "${statefulset_rows}" ]]; then
    printf '%s\n' "${statefulset_rows}" >>"${tmp_file}"
  fi
done

sort -u "${tmp_file}" -o "${tmp_file}"

current_nonzero_rows="$(awk -F $'\t' '$4+0 > 0 {count++} END {print count+0}' "${tmp_file}")"
if kubectl -n "${STATE_NAMESPACE}" get configmap "${STATE_CONFIGMAP}" >/dev/null 2>&1; then
  kubectl -n "${STATE_NAMESPACE}" get configmap "${STATE_CONFIGMAP}" -o jsonpath='{.data.replicas\.tsv}' >"${existing_tmp_file}" || true
  existing_nonzero_rows="$(awk -F $'\t' '$4+0 > 0 {count++} END {print count+0}' "${existing_tmp_file}")"
  if [[ "${current_nonzero_rows}" -eq 0 && "${existing_nonzero_rows}" -gt 0 ]]; then
    echo "Current pause snapshot contains only 0 replica targets; preserving existing ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP} to avoid overwriting the last known good state." >&2
    exit 0
  fi
fi

kubectl -n "${STATE_NAMESPACE}" create configmap "${STATE_CONFIGMAP}" \
  --from-file=replicas.tsv="${tmp_file}" \
  --from-literal=namespaces="${PAUSE_NAMESPACES}" \
  --from-literal=savedAt="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Saved paused workload replica state to ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}."
