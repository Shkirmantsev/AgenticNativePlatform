# ADR-0001: Platform architecture

## Status
Accepted

## Context
We need a production-ready but learnable Kubernetes platform that can run on:

- a local workstation
- a remote mini PC in a home LAN
- a workstation + mini PC hybrid cluster
- a workstation + mini PC + remote worker hybrid cluster

The platform must support:

- GitOps
- encrypted secrets in Git
- self-hosted model runtimes
- external LLM providers
- declarative agents
- service mesh
- agent mesh patterns

## Decision
We use the following layered architecture:

- **OpenTofu or Terraform** for topology and optional external infrastructure
- **Ansible** for machine bootstrap and k3s installation
- **Flux Operator** for Flux lifecycle/bootstrap and **Flux** for Kubernetes GitOps reconciliation
- **MetalLB** for bare-metal LoadBalancer services
- **Istio Ambient Mesh** for service mesh
- **kgateway** for north-south ingress
- **agentgateway** for agent-native LLM/A2A/MCP governance in Kubernetes mode
- **LiteLLM** for provider abstraction and optional local backend normalization
- **KServe** for self-hosted AI serving standardization
- **Ollama** overlay for starter self-hosted local chat model runtime
- **vLLM** overlay for optional CPU self-hosted cloud-native runtime
- **TEI** for embeddings
- **Qdrant + PostgreSQL + Redis** for context
- **kagent + kmcp** for agents and MCP workloads

## Consequences
Benefits:

- clear separation of concerns
- extensible from home-lab to enterprise-style topology
- works with mixed self-hosted and remote model providers
- strongly declarative and GitOps-friendly

Trade-offs:

- more components than a minimal demo stack
- some advanced features depend on hardware capabilities
- KServe is installed even though the starter self-hosted chat runtime may be Ollama or disabled entirely
