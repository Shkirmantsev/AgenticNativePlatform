# Echo MCP sample

This is a starter MCP server project skeleton.

Expected lifecycle:

1. implement your FastMCP or SDK-based server
2. build the container image
3. either:
   - push it to your registry, or
   - save and import it into `k3s` containerd with:
     - `make build-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0`
     - `make save-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar`
      - `make preimport-echo-mcp-image-tarball TOPOLOGY=local ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar`
4. regenerate Flux inputs with the same image:
   - `make flux-values TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0`
   - `make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false`
5. commit and let Flux reconcile it
