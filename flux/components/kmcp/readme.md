# kmcp notes

This repository installs `kmcp` separately through `flux/components/kmcp-core`.

Because of that, the `kagent` Helm releases must keep:

- `kmcp.enabled: false` on `kagent-crds`
- `kmcp.enabled: false` on `kagent`

The sample `echo-mcp` workload in this repository is intentionally implemented as a real
`MCPServer` resource managed by `kmcp`.

The repository also disables direct kagent discovery for that sample with:

```yaml
metadata:
  labels:
    kagent.dev/discovery: "disabled"
```

That is required because this repository intentionally places `agentgateway`
in front of MCP traffic, so `kagent` should consume the gatewayed MCP endpoint
through `RemoteMCPServer`, not auto-discover and bypass the gateway.

Effective MCP path in this repo:

```text
kagent -> RemoteMCPServer -> agentgateway -> kmcp-managed MCP server
```
