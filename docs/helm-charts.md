# Helm charts

## Production path charts

These charts are part of the intended production-style path and are installed through Flux `HelmRelease` resources:
- `charts/litellm-proxy`
- `charts/lmstudio-external`
- `charts/ollama-runtime`
- `charts/vllm-cpu`
- `charts/tei-embeddings`
- `charts/kagent-agents`

## Demo / packaging chart

`charts/ai-runtimes` is kept as a compact demo/manual packaging chart. It is useful for learning and templating, but it is not the default production path in this repository.

## Chart quality notes

The local charts include:
- explicit image tags
- ServiceAccounts for pod-based charts
- `automountServiceAccountToken: false` where Kubernetes API access is not needed
- default `resources.requests` and `resources.limits`, including `ephemeral-storage`
