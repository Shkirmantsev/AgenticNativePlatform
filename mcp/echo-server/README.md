# Echo MCP sample

This directory is now an optional thin Docker wrapper around the official reference server package from:

- `https://github.com/modelcontextprotocol/servers`
- npm package: `@modelcontextprotocol/server-everything`

It runs the official `Everything` server in `streamableHttp` mode on port `3001`. The server exposes a real MCP endpoint at `/mcp`, and one of its tools is `echo`.

The active sample manifest under [echo-mcpserver.yaml](/home/dmytro/workspace/personal_projects/AgenticNativePlatform/apps/platform/kmcp/resources/echo-mcpserver.yaml) no longer requires this image. It uses `node:22-bookworm-slim` directly and installs `@modelcontextprotocol/server-everything` at startup.

Use this Dockerfile only if you explicitly want a prebuilt wrapper image instead of the declarative in-manifest startup flow.

Notes:

- This is an official reference/test server, not a production-hardened business service.
- Installing the package at pod startup is convenient for a sample, but slower and less reproducible than a pinned prebuilt image.
