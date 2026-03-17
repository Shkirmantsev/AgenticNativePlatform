# Helm charts in this repository

These local charts are reconciled by Flux from the **same Git repository** that also contains the Flux manifests.

## Production-style modular charts

- `charts/litellm-proxy`
- `charts/lmstudio-external`
- `charts/ollama-runtime`
- `charts/vllm-cpu`
- `charts/tei-embeddings`
- `charts/kagent-agents`

## Demo / alternative packaging chart

- `charts/ai-runtimes`

This chart is intentionally kept for demos, experiments, and alternative manual Helm workflows. It is not the default production-style path.

## How values are injected

Flux `HelmRelease` objects under `flux/components/*/release.yaml` load values from generated `ConfigMap` objects in `flux/generated/<topology>/`.

Examples:

- `flux/generated/<topology>/litellm-values-configmap.yaml`
- `flux/generated/<topology>/lmstudio-values-configmap.yaml`
- `flux/generated/<topology>/ollama-values-configmap.yaml`
- `flux/generated/<topology>/vllm-values-configmap.yaml`
- `flux/generated/<topology>/tei-values-configmap.yaml`

## Secret handling modes

- `SECRETS_MODE=external`: create Kubernetes Secrets directly from `.env` with `make apply-plaintext-secrets`; Flux does not manage secrets yet.
- `SECRETS_MODE=sops`: encrypt manifests in `flux/secrets/<env>/` and let Flux decrypt them.
- `SECRETS_MODE=plaintext`: commit plain generated secrets under `flux/generated/secrets/<env>/` for disposable lab use only.
