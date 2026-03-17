# ADR-0008: Keep demo assets but separate them from the default production path

## Status
Accepted

## Context
The repository is both a learning project and a production-style starter platform. Some compact charts and demo assets are useful for learning, but they should not blur the default production path.

## Decision
- Keep `charts/ai-runtimes` as a compact demo/manual packaging chart.
- Keep `mcp/` demo assets and sample MCP server content.
- Keep production-style modular charts under `charts/` and install them through Flux `HelmRelease` resources.
- Document clearly which path is default production and which path is for learning/demo use.

## Consequences
- The repository stays useful for learning.
- The production path remains explicit and consistent.
- Demo assets do not need to be removed just because Kubernetes-native equivalents exist.
