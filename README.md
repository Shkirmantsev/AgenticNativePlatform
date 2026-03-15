# Agentic Kubernetes Native Platform


This repository provides a GitOps-first, production-oriented starter platform for **k3s**, **Flux**, **Istio Ambient**, **kgateway (Envoy / Gateway API)**, **agentgateway**, **LiteLLM**, **KServe**, **kagent**, **kmcp**, **Qdrant**, **Redis**, **PostgreSQL**, **TEI**, and optional **Ollama / vLLM** runtime overlays.

## What is included declaratively

- **Terraform**: topology artifacts, generated Ansible inventory, generated MetalLB values, generated LM Studio Endpoints.
- **Ansible**: OS bootstrap and k3s installation on existing hosts.
- **Flux**: GitOps reconciliation entrypoints for local, miniPC, hybrid, and hybrid-remote topologies.
- **HelmRelease resources** for MetalLB, Istio Ambient, kgateway, agentgateway, KServe, Qdrant, Redis, PostgreSQL, and observability.
- **Kubernetes manifests** for LiteLLM, TEI, LM Studio external endpoint wiring, sample MCP and kagent resources.
- **Local Helm charts** in `helm/charts/` for config glue, external service wiring, optional standalone agentgateway demo, and declarative agents.

## Required setup order

1. Copy `.env.example` to `.env`.
2. Copy the selected `terraform.tfvars.example` to `terraform.tfvars` in the chosen topology directory.
3. Run Terraform to generate inventory and topology artifacts.
4. Run Ansible to bootstrap the hosts and install k3s.
5. Install Flux and point it at this repo.
6. Apply one of the cluster roots under `flux/clusters/`.

See `docs/commands.md`, `docs/helm-charts.md`, and `docs/adr/`.

# Agentic Kubernetes Native Platform (v5)

This repository is a **GitOps-first, production-style starter platform** for running agentic AI workloads on Kubernetes.

It is designed to support:
- local-only startup,
- a mini-PC in the home network,
- hybrid local + mini-PC,
- hybrid + remote host,
- remote LLM providers,
- external local-host endpoints such as **LM Studio**,
- optional self-hosted runtimes such as **Ollama** and **vLLM**.

## Default startup mode

The repository now defaults to:
- `TOPOLOGY=local`
- `ENV=dev`
- `RUNTIME=none`

That means:
- the easiest first start is on the local machine,
- the default model is **remote Gemini**,
- self-hosted runtimes are **off by default**.

## Core layers

- **k3s** for the lightweight Kubernetes cluster
- **Terraform** for topology artifacts and optional external infrastructure
- **Ansible** for OS bootstrap and k3s installation on existing hosts
- **Flux** for GitOps reconciliation
- **MetalLB** for bare-metal `LoadBalancer` IPs
- **Istio Ambient** for service mesh
- **kgateway** for Gateway API / Envoy ingress
- **agentgateway** for agent-, MCP-, and LLM-aware routing
- **LiteLLM** for provider abstraction
- **KServe** for Kubernetes-native model serving control plane
- **kagent** for declarative agent runtime
- **Qdrant + Redis + PostgreSQL** for the context layer
- **TEI** for embeddings
- **LM Studio external endpoint** via Kubernetes `Service` + `Endpoints`
- **Ollama** and **vLLM** as optional self-hosted runtime overlays

## Runtime switch

The runtime switch is explicit:

- `RUNTIME=none` — remote-only startup; easiest default
- `RUNTIME=ollama` — in-cluster Ollama runtime
- `RUNTIME=vllm` — in-cluster vLLM CPU runtime (opt-in)

## Quick start

1. Copy `.env.example` to `.env` and adjust values if needed.
2. Generate topology artifacts with Terraform. For `TOPOLOGY=local`, the generated Ansible inventory uses `ansible_connection=local`.
3. Bootstrap the host(s) with Ansible.
4. Install k3s.
5. Install Flux controllers.
6. Apply or bootstrap the desired cluster path.

```bash
cp .env.example .env
make terraform-init TOPOLOGY=local
make terraform-apply TOPOLOGY=local
make bootstrap-hosts TOPOLOGY=local
make install-k3s-server TOPOLOGY=local
make kubeconfig TOPOLOGY=local
make install-flux-local
make apply-cluster TOPOLOGY=local ENV=dev RUNTIME=none
```

## Flux GitOps path

For true Flux Git reconciliation, bootstrap the Git source after the cluster is reachable:

```bash
source .env
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none
make reconcile
```

## Local LM Studio integration

LM Studio runs on the host, not inside k3s. The platform exposes it into the cluster with:
- `Service`: `lmstudio-external.ai-gateway.svc.cluster.local`
- `Endpoints`: pointing to `192.168.1.108:1234` by default

Adjust `flux/components/lmstudio-external/endpoints.yaml` if your host IP changes, or reserve the IP in your router.

## vLLM notes

The `vLLM` runtime is disabled by default. Enable it only when needed:

```bash
make apply-cluster TOPOLOGY=local ENV=dev RUNTIME=vllm
```

Important:
- The default `vLLM` deployment uses the **official CPU image** and a **small model**.
- On x86 hosts without AVX-512 support, the prebuilt image can fail. In that case, build a custom CPU image and replace the image in `flux/components/vllm/deployment.yaml`.
- The service is named `vllm-openai` on purpose so that Kubernetes service environment variables do not collide with `VLLM_*` variables.

## Commands

See [docs/commands.md](docs/commands.md).

## ADRs

See [docs/adr/README.md](docs/adr/README.md).
