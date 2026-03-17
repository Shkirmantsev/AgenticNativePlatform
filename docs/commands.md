# Commands

## Tool installation

```bash
make tools-install-local                               # installs age, sops, kubectl, helm, flux, optional k9s and your chosen IaC CLI
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
make tools-install-local IAC_TOOL=terraform INSTALL_K9S=false
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

## End-to-end topology bootstrap shortcuts

```bash
make cluster-up-local
make cluster-up-minipc
make cluster-up-hybrid
make cluster-up-hybrid-remote
```

## Same repo and remote repo

Flux always reads a **remote Git repository URL**. The usual pattern is:

1. work in this repository locally;
2. push the same repository to GitHub or GitLab;
3. set `GIT_REPO_URL` to that remote URL;
4. let Flux read `./flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>` from the remote repository.

## Runtime switches

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none   SECRETS_MODE=external LMSTUDIO_ENABLED=false
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none   SECRETS_MODE=external LMSTUDIO_ENABLED=true
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=ollama SECRETS_MODE=external LMSTUDIO_ENABLED=false
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=vllm   SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
```

## Secrets without encryption

```bash
make render-plaintext-secrets ENV=dev
make apply-plaintext-secrets ENV=dev
```

## SOPS workflow

```bash
make sops-age-key
make render-sops-secrets ENV=dev
make encrypt-secrets ENV=dev
make sops-bootstrap-cluster
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=sops LMSTUDIO_ENABLED=false
make reconcile
```

## Verify endpoints

```bash
make verify
make test-litellm
make port-forward-kagent
make test-a2a-agent
make port-forward-agentgateway
make test-agentgateway-gemini
make test-agentgateway-openai
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

## Pause / resume / teardown

```bash
make cluster-stop
make cluster-start
make uninstall-k3s TOPOLOGY=local
make terraform-destroy TOPOLOGY=local TF_BIN=tofu
```
