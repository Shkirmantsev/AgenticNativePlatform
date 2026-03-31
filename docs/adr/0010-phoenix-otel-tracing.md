# ADR-0010: Centralized Phoenix tracing for AgentGateway, kagent, and KMCP-managed MCP servers

## Status

Accepted

## Context

The platform already uses Flux, AgentGateway, kagent, KMCP, Prometheus, Grafana, and Loki.
Tracing was still missing across the AI request path, especially for MCP tool execution inside custom MCP servers such as `finnhub-mcp-server`.

A pure gateway-only solution is insufficient because AgentGateway and KMCP can trace routing boundaries, but they cannot see internal tool handler execution inside the Go process.

A sidecar OpenTelemetry collector per MCP server is possible with KMCP, but it would duplicate collector configuration across every MCP server deployment.

## MCP coverage note

Vendor agent charts in `charts/vendor/kagent/charts/*/templates/agent.yaml` reference two distinct MCP endpoints:

- the built-in `kagent` tool server (shared by k8s-agent, istio-agent, helm-agent, kgateway-agent, cilium agents, and argo-rollouts-agent)
- the bundled `grafana-mcp` server used by `observability-agent`

Tracing is therefore enabled declaratively at both layers:

- `kagent-tools.otel.tracing.*` for the shared built-in tool server
- `grafana-mcp.otel.tracing.*` for the bundled Grafana MCP server

The local `grafana-mcp` subchart also enables `--metrics` and a `ServiceMonitor` so the same server is visible in Prometheus/Grafana while Phoenix receives its traces through the shared OTLP collector.

## Decision

Use a centralized OpenTelemetry collector in the `observability` namespace and export traces to both a self-hosted Phoenix deployment and Grafana Tempo.

Enable tracing in three layers:

1. `agentgateway-proxy` via `AgentgatewayPolicy`
2. `kagent` and `kagent-tools` via Helm values
3. custom MCP servers via in-process OpenTelemetry instrumentation

For the Go MCP server `finnhub-mcp-server`, use `mcp-otel-go` middleware together with a small OpenTelemetry bootstrap package that exports OTLP traces to the in-cluster collector.

## Consequences

### Positive

- one GitOps-managed trace backend for the whole AI request path
- no sidecar duplication for every MCP server
- Phoenix adds a dedicated AI tracing and evaluation UI without replacing Prometheus/Grafana/Loki
- KMCP-managed MCP servers still remain easy to onboard: add OTEL env vars and instrument the process

### Negative

- custom MCP servers still need application-level instrumentation
- Phoenix adds another observability component to operate

## Rejected alternative

Use a collector sidecar on every MCP server pod.

This is valid for isolated workloads, but it is not the simplest default for this repository because the platform already has a shared `observability` namespace and a GitOps-managed central control plane.


## MCP server rollout pattern

Apply observability in three levels for every KMCP-managed MCP server:

1. gateway and agent spans for every MCP call through AgentGateway and kagent
2. baseline OTEL runtime environment on every `MCPServer.spec.deployment.env` block
3. in-process instrumentation for first-party MCP servers that we own

This means every MCP server behind KMCP is visible at least at the request-boundary level, while first-party servers such as `finnhub-mcp-server` also expose internal tool spans and Prometheus metrics. Third-party opaque servers such as `echo-mcp` remain boundary-traced until they are wrapped or rebuilt with runtime instrumentation.
