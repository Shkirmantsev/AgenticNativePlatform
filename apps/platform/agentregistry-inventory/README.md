# Agent Registry Inventory

This bundle installs the upstream Agent Registry Inventory control plane from the upstream Git repository through Flux.

Upstream attribution:

- author: Den Vasyliev
- source repository: `https://github.com/den-vasyliev/agentregistry-inventory`
- tracked Flux source: branch `main`

Current integration choices:

- target namespace: `agentregistry`
- Flux source: `GitRepository/flux-system/agentregistry-inventory`
- chart source: upstream `./charts/agentregistry`
- repo-local custom resources: only the staged `DiscoveryConfig`
- default discovery: the local `kagent` namespace
- default exposure: internal `ClusterIP` plus `make open-agentregistry-inventory`
- default external route: disabled on purpose so existing topologies do not gain a new public surface by default
