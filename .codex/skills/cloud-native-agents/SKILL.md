---
name: "cloud-native-agents"
description: "Design, deploy, and operate cloud-native Kubernetes agents, including MCP-based controllers and agentic control planes. Use when work involves Kubernetes-native agent architecture, AgentGateway integration, or Solo.io platform integration."
---

# Cloud Native Agents Skills

Use this skill for designing, deploying, and managing cloud-native Kubernetes agents, including:
- Defining agentic control planes in Kubernetes.
- Implementing MCP servers as Kubernetes controllers or sidecars.
- Interfacing agents with cluster resources and external APIs.
- Managing agent lifecycle, telemetry, and observability.

## Workflow

1. Classify scope first: generic Kubernetes agent control plane, AgentGateway integration, or Solo.io platform integration.
2. Use standard Kubernetes tools for deployment and diagnostics.
3. Read [upstream-current.md](./references/upstream-current.md) when the task touches kagent, kmcp, AgentGateway, kgateway, or ambient operational tradeoffs.
4. Use `https://agentgateway.dev/docs/kubernetes/latest/` for AgentGateway Kubernetes installation and operations guidance.
5. Use `https://www.solo.io/docs` (and linked product docs) for Solo.io product-specific architecture and CRD behavior.
6. Prioritize observability and robust error handling for asynchronous agent tasks.

## Tooling

- Kubernetes controllers/operators.
- MCP client/server implementations for Kubernetes environments.
- Telemetry tools (logs, metrics, traces).
- Primary docs: AgentGateway Kubernetes docs and Solo.io docs.
