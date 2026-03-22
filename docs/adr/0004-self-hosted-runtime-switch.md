# ADR 0004: Self-hosted runtime switch defaults to remote-only

## Status
Accepted

## Context
The platform must support three runtime modes:
- `none` for remote-only startup and debugging,
- `ollama` for an easy in-cluster local model path,
- `vllm` for a more Kubernetes-native self-hosted runtime path.

The current workstation and mini-PC cannot use ROCm. The `vLLM` path therefore has to rely on CPU mode or a future custom image. The upstream prebuilt CPU image is useful for testing, but it may fail on x86 hosts that lack the required AVX-512 instruction set.

## Decision
- The repository default is `TOPOLOGY=local`, `ENV=dev`, `RUNTIME=none`.
- The default starter model path is a **remote Gemini model** through LiteLLM.
- `vLLM` remains available as an explicit opt-in runtime.
- `KServe` remains part of the platform control plane, but no self-hosted vLLM workload is deployed unless `RUNTIME=vllm` is selected.
- `LM Studio` is exposed into the cluster through a Kubernetes `Service` + `Endpoints` object instead of Docker-specific hostnames.

## Consequences
- First startup is lighter and easier to debug.
- The platform still supports both local host endpoints and in-cluster runtimes.
- Operators can switch to `RUNTIME=vllm` later without changing the high-level architecture.
