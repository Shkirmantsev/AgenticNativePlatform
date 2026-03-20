---
name: "kubernetes"
description: "Manage Kubernetes clusters, resources, and troubleshooting. Use when tasks involve kubectl operations, manifest changes, diagnostics, or Kubernetes-native agent deployments. Prioritize kubectl, Kubernetes docs, and AgentGateway Kubernetes docs."
---

# Kubernetes Skills

Use this skill for Kubernetes cluster management, workload operations, and troubleshooting.

## Workflow

1. Use `kubectl` for standard operations.
2. If available, use Kubernetes MCP tools for deeper cluster insight.
3. Read [upstream-current.md](./references/upstream-current.md) when the task touches version-sensitive Kubernetes, HPA behavior, or AgentGateway-on-Kubernetes.
4. Use `https://agentgateway.dev/docs/kubernetes/latest/` for AgentGateway-on-Kubernetes setup, configuration, and runtime troubleshooting.
5. Use official Kubernetes docs (`https://kubernetes.io/docs`) and `kubectl` help for core API behavior.
6. For troubleshooting, inspect events, pod status, `describe`, and logs before suggesting architectural changes.

## Tooling

- Use `kubectl` via terminal.
- Use Kubernetes MCP server (if configured).
- Prioritize documentation in this order: AgentGateway Kubernetes docs for gateway-specific tasks, then official Kubernetes docs.
