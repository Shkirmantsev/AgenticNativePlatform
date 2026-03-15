# Local Helm charts and templates

This repository intentionally contains local Helm charts so the declarative glue layer is visible and reviewable.

## Charts

- `helm/charts/litellm-config`: Deployment, Service, and ConfigMap for LiteLLM.
- `helm/charts/external-services`: Templates for LM Studio `Service + Endpoints`.
- `helm/charts/kagent-agents`: `ModelConfig`, `ModelProviderConfig`, `RemoteMCPServer`, and sample `Agent`.
- `helm/charts/ai-runtimes`: Optional TEI, vLLM, and Ollama runtime templates.
- `helm/charts/agentgateway-standalone-demo`: Standalone-style `config.yaml` demo in Kubernetes with UI on `localhost:15000/ui` after port-forward.

## Why local charts exist in addition to Flux HelmReleases

Third-party platform components such as kgateway, agentgateway, KServe, and Istio are installed from upstream OCI/Helm repositories through Flux `HelmRelease` resources. The local charts in this repository cover the **glue layer**: config, external endpoints, sample agent definitions, and demos.
