# KServe usage in this repository

KServe is installed in Standard mode.

Starter behavior:
- `Ollama` is the default self-hosted chat runtime overlay for home-lab hardware.
- `TEI` is the embedding runtime.
- `KServe` remains in the platform to standardize future self-hosted model serving.

A future iteration can add:
- custom `ServingRuntime`
- `InferenceService`
- model cache
- llm-d or vLLM on suitable hardware
