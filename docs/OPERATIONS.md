# Operations Guide

## Recommended first start

Use the local topology, remote Gemini, no in-cluster chat runtime, and external (non-Git) secrets first.

```bash
cp .env.example .env
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
make cluster-up-local
make install-flux-local
make apply-plaintext-secrets ENV=dev
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
make verify
```

## Supported topologies

- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

Use the corresponding shortcuts:

```bash
make cluster-up-local
make cluster-up-minipc
make cluster-up-hybrid
make cluster-up-hybrid-remote
```

## Runtime switch model

- `RUNTIME=none` keeps self-hosted chat runtimes disabled.
- `RUNTIME=ollama` enables the in-cluster Ollama HelmRelease.
- `RUNTIME=vllm` enables the in-cluster vLLM CPU HelmRelease.
- `LMSTUDIO_ENABLED=true` enables Kubernetes Service+Endpoints glue for an external LM Studio endpoint.

The canonical request path remains:

`kagent -> agentgateway -> LiteLLM -> provider/backend`

## Pause and resume

`make cluster-stop` suspends GitOps reconciliation and scales selected workloads to zero without uninstalling k3s.

`make cluster-start` resumes GitOps reconciliation and lets Flux restore the desired state from Git.

## Encryption modes

- `SECRETS_MODE=external`: easiest first stage. Secrets are created directly from `.env` into the cluster.
- `SECRETS_MODE=sops`: recommended GitOps mode. Encrypted secrets are stored in Git and decrypted by Flux.
- `SECRETS_MODE=plaintext`: disposable lab mode only.
