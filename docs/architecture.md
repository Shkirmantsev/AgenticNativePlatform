# Architecture

## Canonical model

The repository now uses static Git-authored cluster roots under `clusters/`.

Each cluster root points at four top-level staged Flux `Kustomization` objects:

- `platform-infrastructure`
- `platform-secrets`
- `platform-runtime`
- `platform-applications`

The `platform-applications` wrapper then renders child stages:

- `platform-applications-remotes`
- `platform-applications-core`

Those stages compose the shared top-level trees:

- `infrastructure/`
- `apps/`
- `charts/`
- `values/`
- `secrets/`

Staging semantics:

- `platform-infrastructure` installs controllers, CRDs, shared platform releases, and now health-gates on kgateway readiness before later stages proceed
- `platform-secrets` supplies runtime secrets and SOPS-decrypted objects without waiting for infrastructure readiness
- `platform-runtime` waits for infrastructure and secrets, then applies gateway-facing runtime objects such as kgateway routes, AgentGateway resources, observability runtime resources, and KMCP-backed MCP services
- `platform-applications` waits for runtime and secrets, then fans out into the child app stages
- `platform-applications-remotes` serializes remote MCP aliases and gateway-exposed application endpoints ahead of dependent app resources
- `platform-applications-core` applies the remaining application resources after the remotes stage
- `mcpg` follows the split platform pattern: its `HelmRelease` and values land in `platform-infrastructure`, while cluster-scoped `MCPGovernancePolicy` and `GovernanceEvaluation` objects land in `platform-applications-core`

## Platform path

```text
external clients
  -> kgateway /v1 -> agentgateway-llm-edge -> agentgateway -> litellm
  -> kgateway /mcp -> agentgateway-mcp-edge -> agentgateway -> MCP backends
  -> litellm -> Redis-backed router state
  -> remote providers and optional local runtimes
```

```text
kagent
  -> agentgateway /v1
  -> agentgateway /mcp
  -> RemoteMCPServer
```

```text
mcpg
  -> watches agentgateway, kagent, and agentregistry resources
  -> evaluates MCP posture with cluster-scoped governance policy and evaluation resources
  -> exposes an internal dashboard in mcp-governance-system
```

```text
agentregistry-inventory
  -> discovers kagent Agents, MCPServer, RemoteMCPServer, and ModelConfig resources
  -> serves internal UI and API over ClusterIP + port-forward
  -> stays off the default public gateway path
```

```text
observability path
  -> agentgateway spans
  -> kagent spans
  -> MCP server spans
  -> OpenTelemetry Collector
  -> Phoenix
  -> Tempo
  -> Prometheus
  -> Grafana
```

## Topologies

- `local`
- `github-codespace`
- `minipc`
- `hybrid`
- `hybrid-remote`

For `local`, the host bootstrap path also installs a workstation-local OCI pull-through cache before `k3s` starts. `k3s` uses localhost mirrors from `registries.yaml`, so repeated local rebuilds can reuse pulled image layers even when the cluster itself was removed and recreated.

Cluster roots are committed as:

- `clusters/local-dev`
- `clusters/github-codespace-dev`
- `clusters/minipc-dev`
- `clusters/hybrid-dev`
- `clusters/hybrid-remote-dev`
