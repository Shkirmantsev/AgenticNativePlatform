#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

charts=(
  charts/litellm-proxy
  charts/lmstudio-external
  charts/ollama-runtime
  charts/tei-embeddings
  charts/vllm-cpu
)

kustomizations=(
  clusters/local-dev
  clusters/local-dev/infrastructure
  clusters/local-dev/apps
  clusters/local-dev/secrets
)

cd "${ROOT_DIR}"

for chart in "${charts[@]}"; do
  echo "[helm lint] ${chart}"
  helm lint "${chart}"
done

for path in "${kustomizations[@]}"; do
  echo "[kubectl kustomize] ${path}"
  kubectl kustomize "${path}" >/dev/null
done

echo "Configuration validation completed."
