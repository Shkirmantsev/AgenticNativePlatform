#!/usr/bin/env bash
set -euo pipefail

STATE_NAMESPACE="${STATE_NAMESPACE:-flux-system}"
STATE_CONFIGMAP="${PAUSE_STATE_CONFIGMAP:-cluster-pause-state}"
PAUSE_NAMESPACES="${PAUSE_NAMESPACES:-${STOP_NAMESPACES:-}}"

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
  kubectl get namespace "${namespace}" >/dev/null 2>&1 || continue
  kubectl -n "${namespace}" get deployment \
    -o jsonpath='{range .items[*]}deployment{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' \
    2>/dev/null >>"${tmp_file}" || true
  kubectl -n "${namespace}" get statefulset \
    -o jsonpath='{range .items[*]}statefulset{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\n"}{end}' \
    2>/dev/null >>"${tmp_file}" || true
done

sort -u "${tmp_file}" -o "${tmp_file}"

kubectl -n "${STATE_NAMESPACE}" create configmap "${STATE_CONFIGMAP}" \
  --from-file=replicas.tsv="${tmp_file}" \
  --from-literal=namespaces="${PAUSE_NAMESPACES}" \
  --from-literal=savedAt="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Saved paused workload replica state to ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}."
