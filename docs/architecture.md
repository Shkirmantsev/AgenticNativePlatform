# Architecture

## Visual overview

![Current platform architecture](../.assets/architecture-current.svg)

Detailed rendered views:

- [Runtime SVG](../.assets/architecture-current-runtime.svg)
- [GitOps/profile SVG](../.assets/architecture-current-profiles.svg)
- [Runtime WBS SVG](../.assets/architecture-current-runtime-wbs.svg)
- [Profiles WBS SVG](../.assets/architecture-current-profiles-wbs.svg)
- [Runtime PlantUML source](../.assets/architecture-current-runtime.puml)
- [GitOps/profile PlantUML source](../.assets/architecture-current-profiles.puml)

## Canonical deployment model

The canonical bootstrap path in this repository is the staged generated Flux root:

- `platform-bootstrap`
- `platform-infrastructure`
- `platform-applications`

Those are rendered under:

- `flux/generated/<topology>/`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`

The staged roots now render through explicit profile composition:

- bundle Kustomizations under `flux/components/bundles/`
- profile Kustomizations under `flux/components/profiles/`
- topology defaults:
  - `platform-profile-full` for host-based topologies
  - `platform-profile-workspace` for `github-workspace`
    - this workspace-specific profile is now a thin alias of `platform-profile-fast-serving`
- lighter opt-in profiles:
  - `platform-profile-fast`
  - `platform-profile-fast-serving`
  - `platform-profile-fast-context`

Older monolithic `platform-core` / `platform` layouts and static pre-rendered
cluster roots have been retired. New work should use the staged generated-cluster
bootstrap model above.

## Runtime architecture

```text
External clients
  -> kgateway
  -> agentgateway

kagent agents
  -> agentgateway /v1/...  -> LiteLLM -> remote providers and optional local runtimes
  -> agentgateway /mcp/... -> kmcp-managed MCP servers

kmcp
  -> manages MCPServer workloads and transport

KServe
  -> remains installed as the self-hosted model-serving control plane
  -> used for lightweight experiments on local PCs and GitHub workspaces / Codespaces
```

## Key design decisions

### kgateway

`kgateway` is the public north-south entry point.

### agentgateway

`agentgateway` is the protocol-aware AI gateway in front of both:

- OpenAI-compatible LLM traffic under `/v1`
- MCP traffic under `/mcp`

### kagent

`kagent` is the agent runtime.

### kmcp

`kmcp` is not an agent runtime.
It manages MCP servers and their lifecycle.

### KServe

KServe remains installed in this repository.
It is not forced into the default LLM hot path yet, but it remains available for:

- lightweight CPU experiments,
- future self-hosted inference evolution,
- runtime-specific test scenarios.

## Supported topologies

- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`
- `github-workspace`

### github-workspace topology

`github-workspace` is a Docker / `k3d` based developer topology for GitHub workspaces,
Codespaces, and other ephemeral container-first environments.

Differences from `local`:

- no Terraform/OpenTofu host provisioning
- no Ansible host bootstrap
- no MetalLB dependency
- use local port-forwarding for operator access

## MCP path in this repository

The repository intentionally uses the following MCP pattern:

```text
kmcp-managed MCPServer
  -> exposed as a Kubernetes Service
  -> fronted by agentgateway
  -> consumed by kagent through RemoteMCPServer
```

That avoids direct service-to-service MCP wiring from `kagent` to raw MCP Services.

## LLM path in this repository

Default path:

```text
kagent -> agentgateway -> LiteLLM -> provider or optional local runtime
```

That keeps model aliasing and provider normalization centralized.

## Validation strategy

1. bootstrap the remote-provider path first,
2. validate MCP through the bundled `kagent-tool-server` route exposed by `agentgateway`,
3. use the opt-in `samples-echo-mcp` bundle only when you explicitly want the sample `MCPServer`,
4. validate KServe using `hf-tiny-inferenceservice.yaml`,
5. only then test larger self-hosted model paths.
