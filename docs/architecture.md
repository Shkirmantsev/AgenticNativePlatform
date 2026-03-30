# Architecture

## Canonical model

The repository now uses static Git-authored cluster roots under `clusters/`.

Each cluster root points at three staged Flux `Kustomization` objects:

- `platform-infrastructure`
- `platform-secrets`
- `platform-applications`

Those stages compose the shared top-level trees:

- `infrastructure/`
- `apps/`
- `charts/`
- `values/`
- `secrets/`

Staging semantics:

- `platform-infrastructure` installs controllers, CRDs, and shared platform releases
- `platform-secrets` supplies runtime secrets and SOPS-decrypted objects without waiting for infrastructure readiness
- `platform-applications` waits for both stages explicitly
- `mcpg` follows the split platform pattern: its `HelmRelease` and values land in `platform-infrastructure`, while cluster-scoped `MCPGovernancePolicy` and `GovernanceEvaluation` objects land in `platform-applications`

## Platform path

```text
external clients
  -> kgateway
  -> agentgateway
  -> litellm
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
