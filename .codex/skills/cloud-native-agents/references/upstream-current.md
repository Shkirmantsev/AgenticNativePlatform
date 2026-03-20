# Upstream Current References

## Verified On 2026-03-20

- kagent docs hub: https://kagent.dev/docs/kagent
- kagent quickstart: https://kagent.dev/docs/kagent/getting-started/quickstart
- kmcp docs: https://kagent.dev/docs/kmcp
- kgateway latest docs: https://kgateway.dev/docs/envoy/latest/
- AgentGateway Kubernetes docs: https://agentgateway.dev/docs/kubernetes/latest/
- Solo.io ambient background: https://www.solo.io/resources/report/sidecar-less-istio-explained
- Solo.io Agent Gateway update blog: https://www.solo.io/blog/updated-a2a-and-mcp-gateway

## Practical reminders

- kagent quickstart still assumes a simple local install path and OpenAI-backed setup. In this repo, treat it as conceptual reference only; production-style deployment is GitOps-managed through Flux.
- kmcp is the Kubernetes-native MCP layer in this stack. Keep its CRDs and controllers staged ahead of custom resources that consume them.
- Current Agent Gateway material emphasizes Kubernetes Gateway API integration plus protocol-aware MCP and A2A handling. When routes look healthy but traffic still fails, continue from controller status into backend Service, EndpointSlice, and mesh reachability checks instead of assuming the policy CRDs are wrong.
