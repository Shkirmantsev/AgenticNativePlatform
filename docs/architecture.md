# Architecture

## Topologies

The repository supports four topology modes:
- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

These modes determine how Terraform/OpenTofu renders:
- the Ansible inventory
- the LM Studio endpoint values
- the MetalLB address pool manifest
- topology metadata under `flux/generated/<topology>/`

## Layered design

- **Bootstrap and infra artifacts**: OpenTofu/Terraform + Ansible
- **Cluster**: k3s
- **GitOps**: Flux
- **Ingress and mesh**: kgateway + agentgateway + Istio Ambient
- **Provider and backend abstraction**: LiteLLM
- **Declarative agent runtime**: kagent + kmcp
- **Model serving and runtimes**: KServe + TEI + Ollama + vLLM
- **Context**: Qdrant + PostgreSQL + Redis

## Canonical request flow

```text
kagent -> agentgateway -> LiteLLM -> providers/backends
```

This keeps agentgateway as the Kubernetes-native AI-aware gateway while LiteLLM remains the OpenAI-compatible normalization layer for both remote providers and optional local runtimes.

## Runtime semantics

- `LM Studio` stays **outside** Kubernetes and is exposed to the cluster through `Service + Endpoints`
- `Ollama` is an **in-cluster** optional runtime
- `vLLM` is an **in-cluster** optional runtime
- `TEI` is the default in-cluster embedding runtime

## Why KServe remains installed

KServe is part of the platform architecture because it is the Kubernetes-native model serving control plane and future evolution path, even if the first practical self-hosted chat runtime may be Ollama.
