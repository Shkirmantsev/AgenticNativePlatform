# Demo assets

This repository includes Kubernetes-native demo assets:

- `charts/kagent-agents`: packages the sample `ModelConfig`, `Agent`, and `RemoteMCPServer` resources for kagent.
- `charts/ai-runtimes`: an optional umbrella chart that demonstrates how LM Studio glue, TEI, Ollama, and vLLM can be packaged together for manual or alternative GitOps workflows.
- `mcp/echo-server`: a tiny example MCP server implementation for experimentation.

The default platform installation uses the more modular component layout under `flux/components/`, but the charts remain available for demos, local experiments, or alternative packaging.
