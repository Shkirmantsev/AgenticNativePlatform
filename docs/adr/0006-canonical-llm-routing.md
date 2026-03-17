# ADR-0006 Canonical LLM routing path

## Status
Accepted

## Decision
Use one canonical LLM path:

`kagent -> agentgateway -> LiteLLM -> providers/backends`

## Rationale
- kagent uses an OpenAI-compatible `baseUrl` against agentgateway.
- agentgateway can apply policy and routing for AI traffic.
- LiteLLM normalizes remote providers and optional local backends.
- Remote providers can still be routed directly by agentgateway later if LiteLLM is intentionally removed.

## Runtime toggles
- `RUNTIME=none` keeps all in-cluster self-hosted chat runtimes disabled.
- `RUNTIME=ollama` enables the in-cluster Ollama Helm release.
- `RUNTIME=vllm` enables the in-cluster vLLM CPU Helm release.
- `LMSTUDIO_ENABLED=true` adds the external LM Studio Service+Endpoints Helm release.
