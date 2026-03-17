# Agentic Kubernetes Native Platform

This repository is a GitOps-first, production-style starter platform for agentic AI workloads on Kubernetes.

It is designed for these topology modes:
- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

The platform is centered around:
- `k3s` for the lightweight Kubernetes cluster
- `Flux` for GitOps reconciliation from a remote Git repository
- `agentgateway` in Kubernetes mode only
- `LiteLLM` as the canonical provider abstraction layer
- `LM Studio`, `Ollama`, and `vLLM` as optional LiteLLM backends
- `kagent` as the declarative agent runtime
- `Qdrant + Redis + PostgreSQL` as the context layer
- `KServe` as the Kubernetes-native model serving control plane

## Canonical routing path

The intended request path is:

```text
kagent -> agentgateway -> LiteLLM -> providers/backends
```

By default, the repository starts in a simple remote-only mode:
- `TOPOLOGY=local`
- `ENV=dev`
- `RUNTIME=none`
- `LMSTUDIO_ENABLED=false`
- `SECRETS_MODE=external`
- `IAC_TOOL=tofu`

That means the first start uses only a remote Gemini model and keeps local runtimes disabled.

## Repository structure

Use one Git repository for the first stage:

```text
repo/
  charts/
  flux/
  terraform/
  ansible/
  docs/
  scripts/
  mcp/
```

Flux does **not** read your local working directory. It pulls from the **remote Git URL** configured in a `GitRepository` object and then applies a path inside that same remote repository.

### Commit these paths to the remote Git repository

- `charts/`
- `flux/components/`
- `flux/overlays/`
- `flux/generated/<topology>/`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`
- `flux/secrets/<env>/` only when using `SECRETS_MODE=sops`
- `docs/`
- `scripts/`
- `mcp/`

### Do not commit

- `.env`
- local `terraform.tfvars` / `terraform.auto.tfvars`
- `.kube/generated/`
- `ansible/generated/`
- local SOPS private keys
- local plaintext rendered secrets under `.generated/`

## Operator tools

Use:

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
```

This runs the Ansible playbook `ansible/playbooks/install-local-tools.yml`.

The playbook installs:
- `age`
- `sops`
- `kubectl`
- `helm`
- `flux`
- optional `k9s`
- optional `OpenTofu` and/or `Terraform`

### k9s behavior on non-Ubuntu systems

`k9s` is installed through the official GitHub release tarball on Linux instead of a hard Ubuntu-only `.deb` path, and it is skipped with an explicit message on unsupported systems instead of failing the whole playbook.

### OpenTofu and Terraform

The playbook can install `OpenTofu`, `Terraform`, both, or neither.

The default in the Makefile is:

```make
IAC_TOOL ?= tofu
TF_BIN ?= $(if $(filter tofu,$(IAC_TOOL)),tofu,terraform)
```

So by default the repository uses **OpenTofu** as the infrastructure CLI.

You can switch modes at runtime:

```bash
make tools-install-local IAC_TOOL=tofu
make tools-install-local IAC_TOOL=terraform
make tools-install-local IAC_TOOL=both

make terraform-init TOPOLOGY=local TF_BIN=tofu
make terraform-apply TOPOLOGY=local TF_BIN=tofu
```

## First start without Git encryption

This is the easiest startup path.

### 1. Create your local environment file

```bash
cp .env.example .env
```

### 2. Set the minimum values in `.env`

Example:

```env
TOPOLOGY=local
ENV=dev
RUNTIME=none
SECRETS_MODE=external
LMSTUDIO_ENABLED=false
IAC_TOOL=tofu

LOCAL_HOST_IP=192.168.1.108
LMSTUDIO_HOST_IP=192.168.1.108

GIT_REPO_URL=https://github.com/<your-user>/<your-repo>.git
GIT_BRANCH=main

GOOGLE_API_KEY=your-real-key
GEMINI_MODEL=gemini-3.1-flash-lite-preview
LMSTUDIO_EMBEDDING_MODEL=text-embedding-qwen3-embedding-0.6b
OLLAMA_VERSION=v0.18.0
```

### 3. Install local tools

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
```

### 4. Initialize and apply infrastructure artifacts

```bash
make terraform-init TOPOLOGY=local TF_BIN=tofu
make terraform-apply TOPOLOGY=local TF_BIN=tofu
```

### 5. Bootstrap the local host and install k3s

```bash
make bootstrap-hosts TOPOLOGY=local
make install-k3s-server TOPOLOGY=local
make kubeconfig TOPOLOGY=local
```

### 6. Install Flux controllers into the cluster

```bash
make install-flux-local
```

### 7. Create external secrets directly in the cluster

```bash
make apply-plaintext-secrets ENV=dev
```

### 8. Commit and push the repository to your remote Git URL

Flux will only reconcile from the pushed remote repository.

### 9. Bootstrap Flux Git source and reconcile

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
make verify
```

## Runtime modes

### Remote-only

```bash
RUNTIME=none
LMSTUDIO_ENABLED=false
```

Use this for the first stable start.

### Remote Gemini + LM Studio

```bash
RUNTIME=none
LMSTUDIO_ENABLED=true
```

In this mode, LM Studio runs **outside** the cluster as a local desktop/service process, and Kubernetes only exposes it through `Service + Endpoints` so LiteLLM can route to it.

### Remote Gemini + Ollama

```bash
RUNTIME=ollama
LMSTUDIO_ENABLED=false
```

Ollama runs **inside** Kubernetes through a Helm release.

### Remote Gemini + vLLM

```bash
RUNTIME=vllm
LMSTUDIO_ENABLED=false
```

vLLM runs **inside** Kubernetes through a Helm release.

## Changing parameters

The intended lifecycle is:
1. edit values or manifests in Git
2. commit
3. push
4. let Flux reconcile

Do not use manual `helm install` or `helm upgrade` as the main operating model. Flux `GitRepository` and `HelmRelease` are the intended declarative control plane.

## Stop and start the platform without uninstalling the cluster

There is no single generic `kubectl` command that powers off a Kubernetes cluster. The safe portable option is to suspend GitOps reconciliation and scale platform workloads to zero, then resume them later.

Use:

```bash
make cluster-stop
make cluster-start
```

What they do:
- `cluster-stop` suspends Flux reconciliation for the main Git source and Kustomization and scales platform Deployments and StatefulSets to zero in the configured namespaces.
- `cluster-start` resumes Flux and lets Git desired state restore the platform.

## Git encryption with SOPS

For the very first start, use `SECRETS_MODE=external` and create secrets directly in the cluster from `.env` or local helper scripts. This avoids blocking the first bootstrap on encryption.

When you are ready to move to encrypted GitOps:

1. install tools locally:

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
```

2. generate an `age` key locally
3. create or update `.sops.yaml`
4. render plaintext secret manifests
5. encrypt them with `sops`
6. create the Flux decryption secret in `flux-system`
7. switch `SECRETS_MODE=sops`
8. commit and push the encrypted manifests to the same GitOps repo

Keep encrypted manifests in the same repository that Flux reconciles.

## Direct provider routing without LiteLLM

The canonical path uses LiteLLM because it gives a single OpenAI-compatible abstraction layer for remote providers and optional local backends.

If you need it later, `agentgateway` can also be configured to route directly to supported providers such as Gemini or Anthropic without LiteLLM in the middle. Use LiteLLM by default, and only bypass it when you deliberately want provider-specific behavior.

## Useful commands

Install operator tools:

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
```

Initialize infrastructure artifacts:

```bash
make terraform-init TOPOLOGY=local TF_BIN=tofu
make terraform-apply TOPOLOGY=local TF_BIN=tofu
```

Install Flux:

```bash
make install-flux-local
```

Pause platform workloads:

```bash
make cluster-stop
```

Resume platform workloads:

```bash
make cluster-start
```

Verify local state:

```bash
make verify
```

## Installation result example

![Install_start_screenshot1](./assets/make-tools-install-local1.png)

![Install_start_screenshot2](./assets/make-tools-install-local2.png)

![Bootstrap_hosts_screenshot](./assets/bootstrap-hosts.png)

![Install_k3s_server_screenshot](./assets/install-k3s-server.png)

![Kubeconfig_screenshot](./assets/export-kubeconfig.png)


