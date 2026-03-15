# Commands

## Default local remote-only startup

```bash
cp .env.example .env
make terraform-init TOPOLOGY=local
make terraform-apply TOPOLOGY=local
make bootstrap-hosts TOPOLOGY=local
make install-k3s-server TOPOLOGY=local
make kubeconfig TOPOLOGY=local
make install-flux-local
make apply-cluster TOPOLOGY=local ENV=dev RUNTIME=none
```

## Register Git source for Flux

```bash
source .env
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none
make reconcile
```

## Switch to Ollama runtime

```bash
make apply-cluster TOPOLOGY=local ENV=dev RUNTIME=ollama
```

## Switch to vLLM runtime

```bash
make apply-cluster TOPOLOGY=local ENV=dev RUNTIME=vllm
```

## Verify endpoints

```bash
make verify
make test-litellm
make port-forward-kagent
make test-a2a-agent
```

## vLLM image pre-import option B (tarball)

On a connected machine:

```bash
docker pull public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest
docker save public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest -o /tmp/vllm-cpu-release-repo-latest.tar
```

Then import to k3s nodes:

```bash
make preimport-vllm-image-tarball TOPOLOGY=local VLLM_IMAGE_TARBALL=/tmp/vllm-cpu-release-repo-latest.tar
```

## vLLM image pre-import option A (online pre-pull)

```bash
make preimport-vllm-image-online TOPOLOGY=local VLLM_IMAGE=public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest
```


## End-to-end bootstrap shortcuts

```bash
make cluster-up-local TOPOLOGY=local
make cluster-up-minipc TOPOLOGY=minipc
make cluster-up-hybrid TOPOLOGY=hybrid
make cluster-up-hybrid-remote TOPOLOGY=hybrid-remote
```

## agentgateway standalone demo UI

```bash
make helm-template-agentgateway-demo
make port-forward-agentgateway-ui
# then open http://localhost:15000/ui/
```
