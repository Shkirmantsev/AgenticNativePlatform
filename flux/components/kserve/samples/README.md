# KServe samples

These samples are intentionally not part of the default reconcile path.
Use them only after the base platform is healthy.

Available samples:

- `hf-tiny-inferenceservice.yaml`
  Lightweight CPU-only validation path for local PCs and GitHub workspaces / Codespaces.
- `vllm-servingruntime.yaml`
  Custom ServingRuntime for vLLM.
- `vllm-inferenceservice.yaml`
  Example InferenceService using the custom vLLM runtime.

Recommended order:

1. validate the platform with the default remote-provider path,
2. validate MCP through `echo-validation-agent`,
3. then apply `hf-tiny-inferenceservice.yaml`,
4. only after that move on to larger or custom runtimes such as vLLM.
