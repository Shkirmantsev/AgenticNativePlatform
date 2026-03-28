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
agentregistry-inventory
  -> discovers kagent Agents, MCPServer, RemoteMCPServer, and ModelConfig resources
  -> serves internal UI and API over ClusterIP + port-forward
  -> stays off the default public gateway path
```

## Topologies

- `local`
- `github-codespace`
- `minipc`
- `hybrid`
- `hybrid-remote`

Cluster roots are committed as:

- `clusters/local-dev`
- `clusters/github-codespace-dev`
- `clusters/minipc-dev`
- `clusters/hybrid-dev`
- `clusters/hybrid-remote-dev`
