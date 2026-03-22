# Demo assets

This repository includes Kubernetes-native demo assets:

- `flux/components/samples-echo-mcp`: the opt-in Flux bundle for the sample `MCPServer`.
- `flux/components/kagent-resources`: the canonical active `ModelConfig`, `Agent`, and built-in `RemoteMCPServer` resources for kagent.
- `charts/ai-runtimes`: an optional umbrella chart that demonstrates how LM Studio glue, TEI, Ollama, and vLLM can be packaged together for manual or alternative GitOps workflows.
- `mcp/echo-server`: a tiny example MCP server implementation for experimentation.

The default platform installation uses the modular Flux component layout under `flux/components/`.
Older monolithic demo packaging such as `charts/legacy/kagent-agents` is archived only for historical reference.
