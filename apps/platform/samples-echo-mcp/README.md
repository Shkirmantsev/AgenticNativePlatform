# echo-mcp sample bundle

This bundle is intentionally optional.

It mirrors the sample `MCPServer` from `../kmcp/resources` for isolated rendering and experiments.

The sample uses KMCP native package deployment for the official MCP reference package:

```text
@modelcontextprotocol/server-everything@2026.1.26
```

The `MCPServer` resource runs it via `npx` with `transportType: http` and the package's `streamableHttp` mode, and KMCP exposes it on `/mcp` for AgentGateway and `RemoteMCPServer` consumers.

The generated pod is also opted out of Istio ambient with `istio.io/dataplane-mode: none`; in this repo, leaving the sample backend in ambient caused AgentGateway `initialize` requests to fail with upstream connection errors even though direct port-forward access still worked.
