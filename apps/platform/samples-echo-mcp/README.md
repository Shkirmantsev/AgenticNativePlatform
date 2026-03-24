# echo-mcp sample bundle

This bundle is intentionally optional.

It deploys the sample `MCPServer` from `../kmcp-resources`, but it is not part of the default staged application path.

The sample now runs directly from `node:22-bookworm-slim` and installs the official `@modelcontextprotocol/server-everything` package at container startup, so it no longer depends on a custom `echo-mcp` image or topology-specific `ECHO_MCP_IMAGE` injection.
