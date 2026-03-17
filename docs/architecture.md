# Architecture

## Canonical LLM path

`kagent -> agentgateway -> LiteLLM -> provider/runtime`

- `agentgateway` is installed **only in Kubernetes mode** by Helm.
- `LiteLLM` is the provider abstraction layer and the default place where remote providers and optional backends are normalized.
- `LM Studio` is optional and remains external to the cluster; Kubernetes adds only Service+Endpoints glue.
- `Ollama` and `vLLM` are optional in-cluster runtimes.
- `TEI` is the in-cluster embedding runtime by default.
- `Qdrant + Redis + PostgreSQL` form the context layer.

## Packaging model

The default installation uses modular Flux components and local Helm charts:

- `charts/litellm-proxy`
- `charts/lmstudio-external`
- `charts/ollama-runtime`
- `charts/vllm-cpu`
- `charts/tei-embeddings`
- `charts/kagent-agents`

For demos and alternative packaging there is also:

- `charts/ai-runtimes`

## Namespaces

Platform components are separated into namespaces such as `kgateway-system`, `agentgateway-system`, `ai-gateway`, `ai-models`, `context`, `kagent`, and `kserve`. Cross-namespace communication uses namespace-qualified service DNS names.


## Topology modes

- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

The topology-specific inventory and generated values are rendered from Terraform/OpenTofu artifacts and consumed by Ansible and Flux.
