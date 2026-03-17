# kmcp notes

`kagent` v0.7 includes the `kmcp` subproject by default when `kmcp.enabled=true` is set on the `kagent` and `kagent-crds` Helm releases.

This directory contains a small sample workload that can be used as the external endpoint for `RemoteMCPServer`-style testing.

If you want the full `kmcp` controller lifecycle for `MCPServer` resources, follow the official kmcp controller installation flow documented by the project and keep `kmcp.enabled=true` in the kagent releases.
