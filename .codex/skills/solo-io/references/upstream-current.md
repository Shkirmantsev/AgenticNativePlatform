# Upstream Current References

## Verified On 2026-03-20

- kgateway latest docs: https://kgateway.dev/docs/envoy/latest/
- Sidecar-less Istio background: https://www.solo.io/resources/report/sidecar-less-istio-explained
- Agent Gateway update blog: https://www.solo.io/blog/updated-a2a-and-mcp-gateway

## Practical reminders

- Solo’s current Agent Gateway positioning is broader than simple north-south proxying: MCP and A2A awareness, Kubernetes Gateway API integration, traffic policy, and LLM gateway capabilities all sit in the same control plane.
- Ambient mode reduces sidecar operational overhead by shifting traffic handling toward shared infrastructure such as `ztunnel` and optional waypoints. In this repo, that means restart and health logic must keep Istio control-plane dependencies healthy before expecting ambient-enrolled workloads to recover cleanly.
