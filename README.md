# Agentic Kubernetes Native Platform v8

This repository is a GitOps-first, production-style starter platform for agentic AI workloads on Kubernetes.

It is designed for four deployment topologies:
- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

The platform combines:
- `k3s` for the lightweight Kubernetes cluster
- `Terraform` for topology artifacts and optional external infrastructure
- `Ansible` for OS bootstrap and k3s installation on existing hosts
- `Flux` for GitOps reconciliation
- `MetalLB` for bare-metal `LoadBalancer` IPs
- `Istio Ambient` for service mesh
- `kgateway` for Gateway API / Envoy ingress
- `agentgateway` for agent-, MCP-, and LLM-aware routing
- `LiteLLM` for provider abstraction
- `KServe` for Kubernetes-native model serving control plane
- `kagent` for declarative agent runtime
- `Qdrant + Redis + PostgreSQL` for the context layer
- `TEI` for in-cluster embeddings
- `LM Studio` external endpoint via Kubernetes `Service + Endpoints`
- `Ollama` and `vLLM` as optional self-hosted runtime overlays

## Default startup mode

The repository is optimized for the easiest first start:

- `TOPOLOGY=local`
- `ENV=dev`
- `RUNTIME=none`
- `LMSTUDIO_ENABLED=false`
- `SECRETS_MODE=external`

That means:
- first start is **local**
- the default model is **remote Gemini**
- no local runtime is enabled by default
- secrets are created directly in the cluster from `.env`
- Git encryption is **not required** for the first run

## Canonical routing path

The intended canonical request path is:

```text
kagent -> agentgateway -> LiteLLM -> remote providers or optional backends
```

Where:
- `agentgateway` is installed **only in Kubernetes mode**
- `LiteLLM` is the unified provider abstraction layer
- `LM Studio` is optional and **external** to the cluster
- `Ollama` and `vLLM` are optional **in-cluster** runtime Helm releases

## Current defaults

The repository currently uses these defaults:
- Gemini model: `gemini-3.1-flash-lite-preview`
- LM Studio embedding model: `text-embedding-qwen3-embedding-0.6b`
- Ollama version: `v0.18.0`

## Repository layout

Keep everything in **one repo** for the first stage.

```text
repo/
  charts/
  flux/
  terraform/
  ansible/
  docs/
```

Meaning:
- `charts/` contains local Helm charts used by Flux `HelmRelease`
- `flux/` contains GitOps sources, kustomizations, Helm releases, generated values, and optionally encrypted secrets
- `terraform/` contains topology artifact generation and optional external infrastructure
- `ansible/` contains OS bootstrap and k3s installation

### Important Flux rule

Flux reads the **remote Git URL of this same repo** after you push it.
It does **not** read your local working directory directly.

That means your workflow is:
1. edit locally
2. commit
3. push to remote Git
4. Flux pulls from the remote repo URL

## What must be committed to the remote Git repository

You should push these directories and files to the remote Git repository used by Flux:
- `charts/`
- `flux/components/`
- `flux/overlays/`
- `flux/generated/<topology>/`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`
- `flux/secrets/<env>/` only when using `SECRETS_MODE=sops` or `SECRETS_MODE=plaintext`

You should **not** commit:
- `.env`
- local `terraform.tfvars`
- `.kube/generated/`
- `ansible/generated/`
- local SOPS private keys

## How Helm charts and Flux work together

This repository uses Helm charts declaratively through Flux.

The intended operating model is:
- use `make` for bootstrap, rendering, helper tasks, and tests
- use `Git + Flux` for all in-cluster configuration changes
- do **not** use manual `helm install` or `helm upgrade` as the main lifecycle mechanism

### What this means in practice

If you want to change:
- a runtime parameter
- an agent definition
- a LiteLLM backend
- a chart value

then you should:
1. edit the chart values or manifests in Git
2. commit and push the change
3. let Flux reconcile it

`make` is the convenience entrypoint.
Flux is the real declarative reconciler.

## Runtime model options

### Remote-only startup

Use:

```bash
RUNTIME=none
LMSTUDIO_ENABLED=false
```

This means:
- no Ollama in cluster
- no vLLM in cluster
- no LM Studio glue
- only remote Gemini through the canonical path

### Remote Gemini + LM Studio

Use:

```bash
RUNTIME=none
LMSTUDIO_ENABLED=true
```

This means:
- LM Studio is started separately by you on the workstation
- Kubernetes only exposes it through `Service + Endpoints`
- LiteLLM can route to LM Studio as a backend

### Remote Gemini + Ollama

Use:

```bash
RUNTIME=ollama
LMSTUDIO_ENABLED=false
```

This means:
- Ollama runs **inside Kubernetes** through a Helm release
- LiteLLM routes to the Ollama service in cluster

### Remote Gemini + vLLM

Use:

```bash
RUNTIME=vllm
LMSTUDIO_ENABLED=false
```

This means:
- vLLM runs **inside Kubernetes** through a Helm release
- KServe remains the model serving control plane
- LiteLLM routes to the in-cluster vLLM OpenAI-compatible service

## Prerequisites

Before the first run, prepare:
- Ubuntu workstation or laptop
- internet access for the first bootstrap
- remote Git repository URL
- Gemini API key
- optional LM Studio running locally if you want local desktop inference

### Tools

Run:

```bash
make tools-install-local
```

This target currently installs the local operator tooling through Ansible.

### Note about local tool installation

The `tools-install-local` target uses Ansible to install and verify these local operator tools:
- `age`
- `sops`
- `kubectl`
- `helm`
- `flux`
- `jq`
- `jq`
- `curl`
- `git`
- `kubectl`
- `helm`
- `flux`

If `kubectl`, `helm`, or `flux` are not present after running the target, extend the playbook before continuing.

## Environment file

Create your local environment file:

```bash
cp .env.example .env
```

Then edit at least these values:

```env
TOPOLOGY=local
ENV=dev
RUNTIME=none
SECRETS_MODE=external
LMSTUDIO_ENABLED=false

LOCAL_HOST_IP=192.168.1.108
LMSTUDIO_HOST_IP=192.168.1.108

GIT_REPO_URL=https://github.com/<your-user>/<your-repo>.git
GIT_BRANCH=main

GOOGLE_API_KEY=your-real-key
GEMINI_MODEL=gemini-3.1-flash-lite-preview

LMSTUDIO_EMBEDDING_MODEL=text-embedding-qwen3-embedding-0.6b
OLLAMA_VERSION=v0.18.0
```

## Step-by-step first start without encryption

This is the recommended first path.

### 1. Install local tools

```bash
make tools-install-local
```

### 2. Bootstrap the local cluster

```bash
make cluster-up-local
```

This performs the local bootstrap sequence:
- Terraform init/apply for local topology artifacts
- Ansible host bootstrap
- k3s server installation
- kubeconfig export

### 3. Verify the cluster

```bash
make verify
```

### 4. Install Flux controllers

```bash
make install-flux-local
```

### 5. Create secrets directly in the cluster from `.env`

```bash
make apply-plaintext-secrets ENV=dev
```

This is the easiest non-encrypted startup mode.
The secrets are not committed to Git yet.

### 6. Bootstrap Flux against the remote Git repository

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
```

### 7. Reconcile the platform

```bash
make reconcile
```

### 8. Verify the platform

```bash
make verify
```

## How to use the same repo with Flux

Flux uses a `GitRepository` that points to your **remote repository URL**, for example:

```text
https://github.com/<your-user>/<your-repo>.git
```

Inside that repository, Flux reconciles a generated cluster root path such as:

```text
flux/generated/clusters/local-dev-none-external/
```

That generated path is created by the bootstrap target.

### Important generated paths

The following generated files must exist before you bootstrap Flux and must be committed if you want Flux to read them from the remote repo:

- `flux/generated/<topology>/...`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/kustomization.yaml`

The `make bootstrap-flux-git` target renders these automatically.

## Enabling LM Studio

LM Studio is **not** deployed in-cluster as a runtime.
You run it separately on your workstation.
Kubernetes only provides a stable service abstraction.

### 1. Start LM Studio locally

Enable the OpenAI-compatible server on your workstation, for example on:

```text
http://192.168.1.108:1234/v1
```

### 2. Re-bootstrap Flux with LM Studio enabled

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=true
make reconcile
```

### 3. Test LM Studio access from the platform

```bash
make test-lmstudio
```

## Enabling Ollama

Ollama is an **in-cluster runtime** installed through a Helm release.

### 1. Re-bootstrap Flux with the Ollama runtime

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=ollama SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
```

### 2. Test Ollama

```bash
make test-ollama
```

## Enabling vLLM

vLLM is an **in-cluster runtime** installed through a Helm release.

### 1. Re-bootstrap Flux with the vLLM runtime

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=vllm SECRETS_MODE=external LMSTUDIO_ENABLED=false
make reconcile
```

### 2. Test vLLM

```bash
make test-vllm
```

## Optional vLLM image pre-import for k3s

If you want to pre-import a vLLM image into k3s containerd before starting it:

```bash
docker pull public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest
docker save public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest -o /tmp/vllm-cpu-release-repo-latest.tar
make preimport-vllm-image-tarball TOPOLOGY=local VLLM_IMAGE_TARBALL=/tmp/vllm-cpu-release-repo-latest.tar
```

## How to change parameters later

### Change Gemini model

Edit `.env`:

```env
GEMINI_MODEL=gemini-3.1-flash-lite-preview
```

Then regenerate and reconcile:

```bash
make flux-values TOPOLOGY=local
git add flux/generated/local
git commit -m "Update Gemini model"
git push
make reconcile
```

### Change LM Studio embedding model

Edit `.env`:

```env
LMSTUDIO_EMBEDDING_MODEL=text-embedding-qwen3-embedding-0.6b
```

Then regenerate and reconcile:

```bash
make flux-values TOPOLOGY=local
git add flux/generated/local
git commit -m "Update LM Studio embedding model"
git push
make reconcile
```

### Change agents

Edit the relevant files, for example:
- `flux/components/kagent/modelconfigs.yaml`
- `flux/components/kagent/agents.yaml`

Then commit and reconcile:

```bash
git add flux/components/kagent
git commit -m "Update kagent agent config"
git push
make reconcile
```

## How to verify the platform

### Verify the cluster

```bash
make verify
```

### Verify agentgateway

```bash
make port-forward-agentgateway
```

Then in another terminal:

```bash
make test-agentgateway-gemini
make test-agentgateway-openai
```

### Verify kagent

```bash
make port-forward-kagent
make test-a2a-agent
```

## Starting with plaintext secrets only

If you want the easiest startup and do not want Git encryption yet, use:

```bash
SECRETS_MODE=external
```

Then:
- keep secrets in `.env`
- run `make apply-plaintext-secrets ENV=dev`
- do **not** commit secrets to Git

This is the recommended first-stage operating mode.

## Final GitOps encryption with SOPS and age

When you are ready to move secrets into GitOps:

### 1. Generate an age key

```bash
make sops-age-key
```

This creates local files such as:
- `.sops/age.agekey`
- `.sops/age.pub`
- `.sops.yaml`

### 2. Render plaintext secret manifests from `.env`

```bash
make render-sops-secrets ENV=dev
```

### 3. Encrypt the secret manifests

```bash
make encrypt-secrets ENV=dev
```

### 4. Put the age private key into the cluster for Flux

```bash
make sops-bootstrap-cluster
```

### 5. Re-bootstrap Flux in encrypted mode

```bash
make bootstrap-flux-git TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=sops LMSTUDIO_ENABLED=false
make reconcile
```

After this:
- the encrypted manifests live in Git
- Flux decrypts them during reconcile
- `.env` still remains your local source file, but no longer the runtime secret source of truth

## Routing model: agentgateway, LiteLLM, and direct providers

The current canonical routing path is:

```text
kagent -> agentgateway -> LiteLLM -> providers/backends
```

This means:
- `kagent` talks to `agentgateway` through an OpenAI-compatible `/v1` endpoint
- `agentgateway` forwards the request to LiteLLM
- LiteLLM selects the configured backend or remote provider

In the current repository state, `agentgateway` is configured to forward the OpenAI-compatible route to the `litellm` service. This is the default and recommended path for the first stage because it gives you one stable protocol between agents and model backends.

### Can you bypass LiteLLM later?

Yes.

`agentgateway` itself supports direct provider configuration for multiple LLM providers, including Gemini, Anthropic, Bedrock, Vertex AI, OpenAI, and OpenAI-compatible endpoints. If you later decide that you do not want LiteLLM in the middle, you can reconfigure the `AgentgatewayBackend` and related routing resources so that `agentgateway` calls those providers directly.

That gives you two valid operating modes:
- **Canonical default**: `kagent -> agentgateway -> LiteLLM -> provider/runtime`
- **Direct-provider mode**: `kagent -> agentgateway -> provider`

The repository currently implements the first mode by default.

## Stopping and starting the platform without deleting the cluster

Kubernetes does not provide a single generic `kubectl stop cluster` command for shutting down the whole cluster control plane. `kubectl` is the CLI for communicating with the Kubernetes control plane API, and workload resources such as Deployments and StatefulSets control how many Pods should be running. For that reason, the clean portable approach is to **pause GitOps reconciliation and scale platform workloads to zero**, while leaving the control plane and core cluster services running.

This repository now provides these helper targets:

```bash
make cluster-stop
make cluster-start
```

### What `make cluster-stop` does

- suspends the Flux `GitRepository` and root `Kustomization`
- suspends all `HelmRelease` objects in the platform namespaces
- scales Deployments and StatefulSets in the platform namespaces to zero replicas
- keeps the cluster itself running

### What `make cluster-start` does

- resumes Flux reconciliation
- resumes the suspended `HelmRelease` objects
- triggers Flux reconciliation so the desired replica counts from Git are restored

This is intentionally **platform-level stop/start**, not machine power-off and not k3s-specific service management.

## Stop, suspend, and destroy operations

### Pause the platform without deleting the cluster

```bash
make cluster-stop
```

### Resume the platform from Git desired state

```bash
make cluster-start
```

### Suspend Flux reconciliation manually

```bash
flux suspend kustomization platform -n flux-system
flux suspend source git platform -n flux-system
```

### Resume Flux reconciliation manually

```bash
flux resume source git platform -n flux-system
flux resume kustomization platform -n flux-system
```

### Delete plaintext secrets

```bash
make delete-plaintext-secrets ENV=dev
```

### Uninstall k3s

```bash
make uninstall-k3s TOPOLOGY=local
```

### Destroy Terraform artifacts or optional infrastructure

```bash
make terraform-destroy TOPOLOGY=local
```

### Stop LM Studio

If LM Studio is enabled, stop it separately on the workstation.
It is not managed as an in-cluster runtime.

## Recommended first operating path

For the cleanest first start on your laptop:

1. `TOPOLOGY=local`
2. `ENV=dev`
3. `RUNTIME=none`
4. `SECRETS_MODE=external`
5. `LMSTUDIO_ENABLED=false`
6. remote Gemini only

Then later, in this order:
1. enable LM Studio glue
2. try Ollama in cluster
3. test vLLM in cluster
4. move secrets to SOPS

## Related documentation

See also:
- `docs/commands.md`
- `docs/helm-charts.md`
- `docs/adr/`
