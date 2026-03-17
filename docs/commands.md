# Commands

## Tool installation

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
make tools-install-local IAC_TOOL=terraform INSTALL_K9S=true
```

## Default local remote-only startup

```bash
cp .env.example .env
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
make terraform-init TOPOLOGY=local TF_BIN=tofu
make terraform-apply TOPOLOGY=local TF_BIN=tofu
make bootstrap-hosts TOPOLOGY=local
make install-k3s-server TOPOLOGY=local
make kubeconfig TOPOLOGY=local
make install-flux-local
make apply-plaintext-secrets ENV=dev
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
make verify
```

`make install-flux-local`, `make reconcile`, `make verify`, and `make sops-bootstrap-cluster` use `KUBECONFIG=.kube/generated/current.yaml` through the `Makefile`.

## Validate generated manifests locally

```bash
kubectl kustomize flux/generated/local
kubectl kustomize flux/generated/clusters/local-dev-none-external
```

## Register Git source for Flux

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
```

## Switch to LM Studio external backend

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=true
make reconcile
```

## Switch to Ollama runtime

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=ollama SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
```

## Switch to vLLM runtime

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=vllm SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
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

## Stop and start the platform without deleting the cluster

```bash
make cluster-stop
make cluster-start
```

## Bootstrap SOPS decryption in-cluster

```bash
make sops-age-key
make render-sops-secrets ENV=dev
make encrypt-secrets ENV=dev
make sops-bootstrap-cluster
```

## Teardown

```bash
make uninstall-k3s TOPOLOGY=local
make terraform-destroy TOPOLOGY=local TF_BIN=tofu
```
