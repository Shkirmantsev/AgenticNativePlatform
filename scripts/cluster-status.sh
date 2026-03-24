#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
FLUX_BIN="${FLUX_BIN:-flux}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-}"
STATE_NAMESPACE="${STATE_NAMESPACE:-flux-system}"
STATE_CONFIGMAP="${PAUSE_STATE_CONFIGMAP:-cluster-pause-state}"
PAUSE_NAMESPACES="${PAUSE_NAMESPACES:-}"
PLATFORM_KUSTOMIZATIONS="${PLATFORM_KUSTOMIZATIONS:-platform-infrastructure platform-secrets platform-applications}"

print_default_status() {
  flux_cmd get kustomizations -A || true
  flux_cmd get helmreleases -A || true
  kubectl_cmd get pods -A || true
}

kubectl_cmd() {
  if [[ -n "${KUBECONFIG_PATH}" ]]; then
    "${KUBECTL_BIN}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
  else
    "${KUBECTL_BIN}" "$@"
  fi
}

flux_cmd() {
  if [[ -n "${KUBECONFIG_PATH}" ]]; then
    "${FLUX_BIN}" --kubeconfig "${KUBECONFIG_PATH}" "$@"
  else
    "${FLUX_BIN}" "$@"
  fi
}

get_jsonpath() {
  local resource="$1"
  local jsonpath="$2"
  kubectl_cmd -n "${STATE_NAMESPACE}" get "${resource}" -o "jsonpath=${jsonpath}" 2>/dev/null || true
}

if ! kubectl_cmd get namespace "${STATE_NAMESPACE}" >/dev/null 2>&1; then
  print_default_status
  exit 0
fi

source_suspended="$(get_jsonpath "gitrepository/platform" '{.spec.suspend}')"
all_helmrelease_names="$(kubectl_cmd -n "${STATE_NAMESPACE}" get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
all_helmrelease_suspend_values="$(kubectl_cmd -n "${STATE_NAMESPACE}" get helmrelease -o jsonpath='{range .items[*]}{.spec.suspend}{"\n"}{end}' 2>/dev/null || true)"

existing_kustomizations=0
suspended_kustomizations=0
for kustomization in ${PLATFORM_KUSTOMIZATIONS}; do
  if ! kubectl_cmd -n "${STATE_NAMESPACE}" get kustomization "${kustomization}" >/dev/null 2>&1; then
    continue
  fi
  existing_kustomizations=$((existing_kustomizations + 1))
  suspended_value="$(get_jsonpath "kustomization/${kustomization}" '{.spec.suspend}')"
  if [[ "${suspended_value}" == "true" ]]; then
    suspended_kustomizations=$((suspended_kustomizations + 1))
  fi
done

helmrelease_count=0
if [[ -n "${all_helmrelease_names}" ]]; then
  helmrelease_count="$(printf '%s\n' "${all_helmrelease_names}" | sed '/^$/d' | wc -l | tr -d ' ')"
fi

suspended_helmreleases=0
if [[ -n "${all_helmrelease_suspend_values}" ]]; then
  suspended_helmreleases="$(printf '%s\n' "${all_helmrelease_suspend_values}" | grep -c '^true$' || true)"
fi

pause_state_present=0
if kubectl_cmd -n "${STATE_NAMESPACE}" get configmap "${STATE_CONFIGMAP}" >/dev/null 2>&1; then
  pause_state_present=1
fi

paused_cluster=0
if [[ "${pause_state_present}" -eq 1 && "${source_suspended}" == "true" && "${existing_kustomizations}" -gt 0 && "${existing_kustomizations}" -eq "${suspended_kustomizations}" ]]; then
  if [[ "${helmrelease_count}" -eq 0 || "${helmrelease_count}" -eq "${suspended_helmreleases}" ]]; then
    paused_cluster=1
  fi
fi

if [[ "${paused_cluster}" -ne 1 ]]; then
  print_default_status
  exit 0
fi

saved_at="$(get_jsonpath "configmap/${STATE_CONFIGMAP}" '{.data.savedAt}')"
saved_namespaces="$(get_jsonpath "configmap/${STATE_CONFIGMAP}" '{.data.namespaces}')"

echo "Cluster state: PAUSED"
echo "Flux source, staged kustomizations, and HelmReleases are suspended on purpose."
echo "Historical Flux READY=False values are omitted while paused because they reflect the last reconcile before suspension."
if [[ -n "${saved_at}" || -n "${saved_namespaces}" ]]; then
  echo "Pause snapshot: ConfigMap/${STATE_NAMESPACE}/${STATE_CONFIGMAP} savedAt=${saved_at:-unknown} namespaces=${saved_namespaces:-unknown}"
fi
echo
echo "Suspended staged kustomizations: ${suspended_kustomizations}/${existing_kustomizations}"
echo "Suspended HelmReleases: ${suspended_helmreleases}/${helmrelease_count}"
echo
echo "Paused namespace workloads:"
kubectl_cmd get deploy,statefulset -A -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas' \
  | awk 'NR==1 || index(" '"${PAUSE_NAMESPACES}"' ", " " $2 " ")'
echo
echo "Pods still running by design:"
kubectl_cmd get pods -A || true
