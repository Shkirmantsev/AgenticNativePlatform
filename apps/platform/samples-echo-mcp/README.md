# echo-mcp sample bundle

This bundle is intentionally optional.

It deploys the sample `MCPServer` from `../kmcp-resources`, but it is not part of the default staged application path.

Use the rendered topology-specific path under:

- `apps/platform/samples-echo-mcp`

That rendered path injects the `ECHO_MCP_IMAGE` value from generated Flux inputs.
