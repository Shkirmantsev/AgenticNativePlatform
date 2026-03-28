# ADR 0009: Integrate Agent Registry Inventory as an internal Flux-sourced control plane

## Status

Accepted

## Context

The repository already exposes kagent, KMCP, AgentGateway, and supporting context services through staged Flux reconciliation. We want Agent Registry Inventory in the same GitOps path, but without widening the default public surface or carrying a growing repo-local fork of upstream chart files.

The upstream Inventory project is authored by Den Vasyliev and published at `https://github.com/den-vasyliev/agentregistry-inventory`. The repository now tracks that source directly on branch `main`.

## Decision

- Create a Flux `GitRepository` for `https://github.com/den-vasyliev/agentregistry-inventory` on branch `main`.
- Reconcile the upstream `./charts/agentregistry` chart through a repo-local `HelmRelease` in `apps/platform/agentregistry-inventory/core/`.
- Stage the Helm release in `clusters/*/infrastructure/kustomization.yaml`, alongside other controller/core Helm releases.
- Stage the repo-local `DiscoveryConfig` in `clusters/*/apps/kustomization.yaml`, after the infrastructure stage, because the chart owns the `DiscoveryConfig` CRD.
- Keep the default exposure internal-only:
  - namespace `agentregistry`
  - `ClusterIP` service
  - no default `HTTPRoute`
  - operator access via `make open-agentregistry-inventory`
- Ship a default local `DiscoveryConfig` that catalogs `kagent` namespace `Agent`, `MCPServer`, `RemoteMCPServer`, and `ModelConfig` resources with `deployEnabled: false`.
- Make the release depend on `kmcp` and `kagent` so Inventory does not race the runtime CRDs it catalogs.

## Consequences

- Existing topologies gain Inventory without changing their default north-south operator access shape.
- The controller chart and CRDs now follow upstream Git directly, which reduces repo-local drift but accepts upstream branch movement as part of reconciliation behavior.
- Inventory CRDs arrive in the infrastructure stage, while repo-local Inventory custom resources stay in the later applications stage where the CRD already exists.
- Public or gateway-backed Inventory exposure remains a separate deliberate decision, rather than an implicit side effect of installation.
