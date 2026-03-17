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
- clear operational separation between bootstrap, reconciliation, routing, runtimes, and the context layer

## Decision
We use the following layered architecture:

- **k3s** for the lightweight Kubernetes cluster
- **OpenTofu or Terraform** for topology artifacts and optional external infrastructure
- **Ansible** for machine bootstrap and k3s installation on existing hosts
- **Flux** for Kubernetes GitOps
- **MetalLB** for bare-metal LoadBalancer services
- **Istio Ambient Mesh** for service mesh
- **kgateway** for north-south ingress on Gateway API / Envoy
- **agentgateway** for Kubernetes-native agent, LLM, A2A, and MCP-aware routing
- **LiteLLM** for provider abstraction and backend normalization
- **KServe** for self-hosted AI serving standardization and future runtime evolution
- **Ollama** overlay for an easy first in-cluster chat model runtime
- **vLLM** overlay for a more Kubernetes-native self-hosted runtime path
- **TEI** for embeddings
- **Qdrant + PostgreSQL + Redis** for the context layer
- **kagent + kmcp** for declarative agents and MCP workloads

## Consequences
Benefits:

- clear separation of concerns
- extensible from home-lab to enterprise-like topologies
- works with mixed self-hosted and remote model providers
- strongly declarative and GitOps-first
- allows a simple remote-only first start before enabling heavier in-cluster runtimes

Trade-offs:

- more components than a minimal demo stack
- some advanced features depend on hardware capabilities
- KServe is installed even though the easiest first self-hosted chat runtime may still be Ollama
- operators must understand the difference between bootstrap tooling, GitOps reconciliation, and runtime overlays
