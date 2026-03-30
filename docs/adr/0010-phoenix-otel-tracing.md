# ADR-0010: Centralized Phoenix tracing for AgentGateway, kagent, and KMCP-managed MCP servers

## Status

Accepted

## Context

The platform already uses Flux, AgentGateway, kagent, KMCP, Prometheus, Grafana, and Loki.
Tracing was still missing across the AI request path, especially for MCP tool execution inside custom MCP servers such as `finnhub-mcp-server`.

A pure gateway-only solution is insufficient because AgentGateway and KMCP can trace routing boundaries, but they cannot see internal tool handler execution inside the Go process.

A sidecar OpenTelemetry collector per MCP server is possible with KMCP, but it would duplicate collector configuration across every MCP server deployment.

## Decision

Use a centralized OpenTelemetry collector in the `observability` namespace and export traces to a self-hosted Phoenix deployment installed from the Phoenix OCI Helm chart.

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
