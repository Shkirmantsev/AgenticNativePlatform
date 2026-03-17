# Platform composition

`platform-core` contains the always-on base platform and installs:

- base namespaces
- source definitions
- MetalLB
- Istio Ambient
- kgateway
- agentgateway (Kubernetes mode only)
- LiteLLM
- KServe
- TEI
- Qdrant
- PostgreSQL
- Redis
- observability
- kagent
- kagent sample resources via the `kagent-agents` chart
- kmcp sample resources

Optional runtime layers are selected through the generated cluster root:

- `platform-runtime-none`
- `platform-runtime-ollama`
- `platform-runtime-vllm`

Optional LM Studio glue is added only when `LMSTUDIO_ENABLED=true`.
