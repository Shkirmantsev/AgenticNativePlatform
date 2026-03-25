# Echo MCP sample

This directory is an optional thin Docker wrapper around the official reference server package from:

- `https://github.com/modelcontextprotocol/servers`
- npm package: `@modelcontextprotocol/server-everything`

It runs the official `Everything` server in `streamableHttp` mode on port `3001`. The server exposes a real MCP endpoint at `/mcp`, and one of its tools is `echo`.

The active sample manifest under [echo-mcpserver.yaml](/home/dmytro/workspace/personal_projects/AgenticNativePlatform/apps/platform/kmcp/resources/echo-mcpserver.yaml) now uses KMCP native `stdio` packaging with:

- `cmd: npx`
- `args: ["@modelcontextprotocol/server-everything@2026.1.26"]`

Use this Dockerfile only if you explicitly want a separate prebuilt wrapper image instead of KMCP-managed package execution.

Notes:

- This is an official reference/test server, not a production-hardened business service.
- KMCP native `npx` packaging is the preferred path for this sample because it avoids a custom image wrapper while still letting the controller expose the MCP server over streamable HTTP.
