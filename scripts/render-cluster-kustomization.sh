#!/usr/bin/env bash
set -euo pipefail
TOPOLOGY="${TOPOLOGY:-local}"
ENVIRONMENT="${ENV:-dev}"
RUNTIME="${RUNTIME:-none}"
SECRETS_MODE="${SECRETS_MODE:-external}"
LMSTUDIO_ENABLED="${LMSTUDIO_ENABLED:-false}"
OUT_DIR="flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"
CLUSTER_PATH="./flux/generated/clusters/${TOPOLOGY}-${ENVIRONMENT}-${RUNTIME}-${SECRETS_MODE}"

case "${RUNTIME}" in
  none|ollama|vllm) ;;
  *)
    echo "Unsupported runtime: ${RUNTIME}" >&2
    exit 1
    ;;
esac

case "${SECRETS_MODE}" in
  external|sops) ;;
  *)
    echo "Unsupported secrets mode: ${SECRETS_MODE}" >&2
    exit 1
    ;;
esac

case "${LMSTUDIO_ENABLED}" in
  true|false) ;;
  *)
    echo "LMSTUDIO_ENABLED must be 'true' or 'false', got: ${LMSTUDIO_ENABLED}" >&2
    exit 1
    ;;
esac

mkdir -p "${OUT_DIR}"
mkdir -p "${OUT_DIR}/bootstrap" "${OUT_DIR}/infrastructure" "${OUT_DIR}/apps"
rm -f "${OUT_DIR}/bootstrap"/generated-*.yaml "${OUT_DIR}/apps"/generated-*.yaml

bootstrap_generated=()
apps_generated=()
if [[ -d "flux/generated/${TOPOLOGY}" ]]; then
  while IFS= read -r -d '' manifest; do
    name="$(basename "${manifest}")"
    case "${name}" in
      kustomization.yaml|topology-values.yaml)
        continue
        ;;
      metallb-values.yaml)
        cp "${manifest}" "${OUT_DIR}/apps/generated-${name}"
        apps_generated+=("generated-${name}")
        ;;
      *)
        cp "${manifest}" "${OUT_DIR}/bootstrap/generated-${name}"
        bootstrap_generated+=("generated-${name}")
        ;;
    esac
  done < <(find "flux/generated/${TOPOLOGY}" -maxdepth 1 -type f -name '*.yaml' -print0 | sort -z)
fi

{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - platform-bootstrap.yaml
  - platform-infrastructure.yaml
  - platform-applications.yaml
EOF
} > "${OUT_DIR}/kustomization.yaml"

{
cat <<EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-bootstrap
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 10m
  sourceRef:
    kind: GitRepository
    name: platform
  path: ${CLUSTER_PATH}/bootstrap
EOF
if [[ "${SECRETS_MODE}" == "sops" ]]; then
  cat <<EOF
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF
fi
} > "${OUT_DIR}/platform-bootstrap.yaml"

cat <<EOF > "${OUT_DIR}/platform-infrastructure.yaml"
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-infrastructure
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 10m
  dependsOn:
    - name: platform-bootstrap
  sourceRef:
    kind: GitRepository
    name: platform
  path: ${CLUSTER_PATH}/infrastructure
EOF

cat <<EOF > "${OUT_DIR}/platform-applications.yaml"
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: platform-applications
  namespace: flux-system
spec:
  interval: 10m
  prune: true
  wait: true
  timeout: 10m
  dependsOn:
    - name: platform-infrastructure
  sourceRef:
    kind: GitRepository
    name: platform
  path: ${CLUSTER_PATH}/apps
EOF

{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../components/base
  - ../../../../components/sources
EOF
for generated_file in "${bootstrap_generated[@]}"; do
  echo "  - ${generated_file}"
done
if [[ "${SECRETS_MODE}" == "sops" ]]; then
  echo '  - ../../../../secrets/'"${ENVIRONMENT}"
fi
} > "${OUT_DIR}/bootstrap/kustomization.yaml"

{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../components/platform-infrastructure
  - ../../../../components/platform-runtime-${RUNTIME}
EOF
if [[ "${LMSTUDIO_ENABLED}" == "true" ]]; then
  echo '  - ../../../../components/platform-lmstudio'
fi
} > "${OUT_DIR}/infrastructure/kustomization.yaml"

{
cat <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../components/platform-applications
EOF
for generated_file in "${apps_generated[@]}"; do
  echo "  - ${generated_file}"
done
echo '  - ../../../../overlays/'"${ENVIRONMENT}"
} > "${OUT_DIR}/apps/kustomization.yaml"

echo "Rendered ${OUT_DIR}/kustomization.yaml"
