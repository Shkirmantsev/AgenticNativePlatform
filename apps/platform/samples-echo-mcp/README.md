# echo-mcp sample bundle

This bundle is intentionally optional.

It deploys the sample `MCPServer` from `../kmcp-resources`, but it is not part of the default staged application path.

The sample uses KMCP native package deployment for the official MCP reference package:

```text
@modelcontextprotocol/server-everything@2026.1.26
```

The `MCPServer` resource runs it via `npx` with `transportType: stdio`, and KMCP exposes it over streamable HTTP for AgentGateway and `RemoteMCPServer` consumers.
