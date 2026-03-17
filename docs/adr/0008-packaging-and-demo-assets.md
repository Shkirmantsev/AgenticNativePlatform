# ADR-0008 Packaging model and demo assets

## Status
Accepted

## Decision
Keep the default installation modular and Flux-driven, but preserve demo/alternative packaging assets in the repository.

## Details
- The production-style default uses modular Flux components and local Helm charts per capability.
- `charts/kagent-agents` packages sample kagent resources and is used by Flux.
- `charts/ai-runtimes` is kept as an alternative umbrella chart for demos, experiments, and manual Helm workflows.
- `mcp/echo-server` remains in the repository as a reference MCP implementation for local experiments and future kmcp packaging.

## Consequences
- The repository remains usable both as a production-style starter and as a teaching/demo artifact.
- Demo assets are explicit and documented instead of being accidentally removed during refactors.
