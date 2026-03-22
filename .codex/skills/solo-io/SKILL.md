---
name: "solo-io"
description: "Manage Solo.io platform components including Gloo Gateway, Gloo Mesh, and related Kubernetes resources. Use when tasks involve Solo.io installation, configuration, upgrades, traffic policy, mesh connectivity, or troubleshooting."
---

# Solo.io Skills

Use this skill for Solo.io ecosystem operations on Kubernetes.

## Workflow

1. Identify product scope first: Gloo Gateway, Gloo Mesh, or a broader Gloo Platform component.
2. Read [upstream-current.md](./references/upstream-current.md) when the task touches kgateway, ambient tradeoffs, or Solo’s current Agent Gateway positioning.
3. Use `https://www.solo.io/docs` as the entry point and follow product-specific docs from there.
4. Prioritize official Solo docs for CRDs, version compatibility, control-plane behavior, and upgrade paths.
5. Troubleshoot by inspecting Solo custom resources, controller logs, and data-plane connectivity.

## Tooling

- Use `kubectl` plus Solo CLI tooling (`gloo`, `meshctl`) when available.
- Use Solo.io docs as the primary source of truth.
