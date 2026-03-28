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

# Older snapshots could concatenate records when command substitution stripped
# the final newline from one resource list before the next list was appended.
perl -0pi -e 's/([0-9]+)(deployment|statefulset)\t/$1\n$2\t/g' "${tmp_file}"

if [[ ! -s "${tmp_file}" ]]; then
  echo "Saved pause state is empty in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}; skipping replica restore."
  exit 0
fi

saved_rows="$(awk 'END {print NR+0}' "${tmp_file}")"
saved_nonzero_rows="$(awk -F $'\t' '$4+0 > 0 {count++} END {print count+0}' "${tmp_file}")"
if [[ "${saved_rows}" -gt 0 && "${saved_nonzero_rows}" -eq 0 ]]; then
  echo "Saved pause state in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP} contains only 0 replica targets; refusing restore because the snapshot appears stale." >&2
  echo "Bring the workloads back to the intended replica counts once, then run make cluster-pause again to refresh the snapshot." >&2
  exit 2
fi

restored=0
line_number=0
while IFS=$'\t' read -r resource namespace name replicas extra_fields; do
  line_number=$((line_number + 1))
  [[ -n "${resource}${namespace}${name}${replicas}${extra_fields}" ]] || continue
  if [[ -n "${extra_fields}" || -z "${resource}" || -z "${namespace}" || -z "${name}" || ! "${replicas}" =~ ^[0-9]+$ ]]; then
    echo "Malformed pause snapshot row ${line_number} in ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP}: ${resource}\t${namespace}\t${name}\t${replicas}${extra_fields:+\t${extra_fields}}" >&2
    exit 1
  fi
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
