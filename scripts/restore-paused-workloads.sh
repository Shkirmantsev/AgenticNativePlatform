#!/usr/bin/env bash
set -euo pipefail

STATE_NAMESPACE="${STATE_NAMESPACE:-flux-system}"
STATE_CONFIGMAP="${PAUSE_STATE_CONFIGMAP:-cluster-pause-state}"

./scripts/require-kube-apiserver.sh "restoring paused workload state"

if ! configmap_check="$(
  kubectl -n "${STATE_NAMESPACE}" get configmap "${STATE_CONFIGMAP}" -o name 2>&1
)"; then
  if grep -qi 'not found' <<<"${configmap_check}"; then
    echo "No saved pause state found in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}; skipping replica restore."
    exit 0
  fi
  echo "Failed to query ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}: ${configmap_check}" >&2
  exit 1
fi

if [[ -z "${configmap_check}" ]]; then
  echo "No saved pause state found in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}; skipping replica restore."
  exit 0
fi

tmp_file="$(mktemp)"
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

kubectl -n "${STATE_NAMESPACE}" get configmap "${STATE_CONFIGMAP}" -o jsonpath='{.data.replicas\.tsv}' >"${tmp_file}"

if [[ ! -s "${tmp_file}" ]]; then
  echo "Saved pause state is empty in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}; skipping replica restore."
  exit 0
fi

restored=0
while IFS=$'\t' read -r resource namespace name replicas; do
  [[ -n "${resource}" && -n "${namespace}" && -n "${name}" && -n "${replicas}" ]] || continue
  kubectl get namespace "${namespace}" >/dev/null 2>&1 || continue
  kubectl -n "${namespace}" get "${resource}" "${name}" >/dev/null 2>&1 || continue

  current_replicas="$(kubectl -n "${namespace}" get "${resource}" "${name}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  if [[ "${current_replicas}" == "${replicas}" ]]; then
    continue
  fi

  kubectl -n "${namespace}" scale "${resource}/${name}" --replicas="${replicas}"
  restored=$((restored + 1))
done <"${tmp_file}"

echo "Restored ${restored} scaled workload replica values from ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}."
