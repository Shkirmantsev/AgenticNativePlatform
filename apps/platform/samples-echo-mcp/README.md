# echo-mcp sample bundle

This bundle is intentionally optional.

It deploys the sample `MCPServer` from `../kmcp-resources`, but it is not part of the default staged application path.

The sample uses KMCP native package deployment for the official MCP reference package:

```text
@modelcontextprotocol/server-everything@2026.1.26
```

The `MCPServer` resource runs it via `npx` with `transportType: http` and the package's `streamableHttp` mode, and KMCP exposes it on `/mcp` for AgentGateway and `RemoteMCPServer` consumers.

The generated pod is also opted out of Istio ambient with `istio.io/dataplane-mode: none`; in this repo, leaving the sample backend in ambient caused AgentGateway `initialize` requests to fail with upstream connection errors even though direct port-forward access still worked.
