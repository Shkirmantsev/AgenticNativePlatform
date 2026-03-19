# Echo MCP sample

This directory is now a thin Docker wrapper around the official reference server package from:

- `https://github.com/modelcontextprotocol/servers`
- npm package: `@modelcontextprotocol/server-everything`

It runs the official `Everything` server in `streamableHttp` mode on port `3001`. The server exposes a real MCP endpoint at `/mcp`, and one of its tools is `echo`.

Expected lifecycle:

1. build the container image
2. either:
   - push it to your registry, or
   - save and import it into `k3s` containerd with:
     - `make build-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0`
     - `make save-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar`
     - `make preimport-echo-mcp-image-tarball TOPOLOGY=local ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar`
3. regenerate Flux inputs with the same image:
   - `make flux-values TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0`
   - `make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false`
4. commit and let Flux reconcile it

Notes:

- This is an official reference/test server, not a production-hardened business service.
- The local build/import/Flux workflow in this repo remains the same.
