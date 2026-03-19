# Commands

## Tool installation

```bash
make tools-install-local IAC_TOOL=tofu INSTALL_K9S=true
make tools-install-local IAC_TOOL=terraform INSTALL_K9S=true
```

## One-command bootstrap

```bash
cp .env.example .env
# edit .env for your machine and credentials
make run-cluster-from-scratch
```

This is the preferred first-run command.
It installs local tools, brings up the selected topology, installs Flux, applies the initial secrets, renders Flux inputs, bootstraps the Git source, reconciles the staged Kustomizations, and prints cluster status.

After `terraform-apply` writes the topology-specific inputs, it renders the tracked files under `flux/generated/<topology>/` and `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`. If those renders change tracked files, the target stops before host bootstrap continues and asks you to commit and push them first.

Useful follow-up commands:

```bash
make cluster-status
make verify
make k9s-local
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

`make install-flux-local`, `make reconcile`, `make verify`, `make cluster-status`, and `make sops-bootstrap-cluster` use `.kube/generated/current.yaml` through explicit `kubectl` / `flux` binding in the `Makefile`.

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

`make reconcile` now reconciles `platform-bootstrap` first, then force-reconciles HelmReleases before waiting on the higher staged Kustomizations.

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
make cluster-status
make k9s-local
make open-research-access
make test-a2a-agent
make test-agentgateway-openai
make test-litellm
make close-research-access
```

If `k9s` looks empty, run it against the repo kubeconfig and all namespaces:

```bash
make k9s-local
```

## Local operator access

Open all common localhost access paths in the background:

```bash
make open-research-access
```

Close them:

```bash
make close-research-access
```

URLs made available by `make open-research-access`:

- `http://localhost:8080` kagent UI
- `http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json` sample A2A card
- `http://localhost:15000/v1/models` AgentGateway OpenAI-compatible API
- `http://localhost:4000/v1/models` LiteLLM
- `http://localhost:3000` Grafana
- `http://localhost:9090` Prometheus
- `http://localhost:6333/dashboard` Qdrant

If one of those commands fails, the target now reports whether:

- the Service has no ready endpoints
- or the local port is already in use

Override a busy localhost port like this:

```bash
make open-litellm LITELLM_LOCAL_PORT=14000
make port-forward-agentgateway AGENTGATEWAY_LOCAL_PORT=16000
```

LiteLLM requires the master-key header:

```bash
curl -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-change-me}" http://localhost:4000/v1/models
```

AgentGateway can be tested the same way:

```bash
curl -H "Authorization: Bearer ${LITELLM_MASTER_KEY:-change-me}" http://localhost:15000/v1/models
```

If MetalLB has assigned an external IP to `agentgateway-proxy`, the external URL is:

```text
http://<metallb-ip>:8080/v1/models
```

Open or close one endpoint at a time:

```bash
make open-kagent-ui
make close-kagent-ui
make open-kagent-a2a
make close-kagent-a2a
make open-agentgateway
make close-agentgateway
make open-litellm
make close-litellm
make open-grafana
make close-grafana
make open-prometheus
make close-prometheus
make open-qdrant
make close-qdrant
```

Foreground alternatives:

```bash
make port-forward-kagent-ui
make port-forward-kagent
make port-forward-agentgateway
make port-forward-litellm
make port-forward-grafana
make port-forward-prometheus
make port-forward-qdrant
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

## echo-mcp local image import without pushing

Build and import the optional sample MCP image into `k3s` containerd:

```bash
make build-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0
make save-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
make preimport-echo-mcp-image-tarball TOPOLOGY=local ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
```

Or use the shortcut:

```bash
make prepare-echo-mcp-image-local TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
```

Then set the same image tag in:

```bash
make flux-values TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0
make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
```

The final image value is injected from `ECHO_MCP_IMAGE` into the generated applications stage, not hard-coded in the component YAML.

These targets create `/var/lib/rancher/k3s/agent/images/` automatically if it is missing.
They also import the tarball into `k3s` containerd immediately with `k3s ctr images import`.
Run them as your normal user; `sudo make ...` is not required. On a local workstation, the ad-hoc Ansible command will prompt through `sudo` if it needs your password.

## End-to-end bootstrap shortcuts

```bash
make cluster-up-local TOPOLOGY=local
make cluster-up-minipc TOPOLOGY=minipc
make cluster-up-hybrid TOPOLOGY=hybrid
make cluster-up-hybrid-remote TOPOLOGY=hybrid-remote
```

## Pause and resume the platform without deleting the cluster

```bash
make cluster-pause
make cluster-resume
```

These targets now operate on the staged Flux objects as well as the top-level `platform` object. If startup still looks slow, inspect the staged status directly:
`cluster-pause` pauses platform workloads; it does not stop system namespaces or DaemonSets, so `flux-system`, `kube-system`, `cert-manager`, `metallb-system`, `istio-cni`, `ztunnel`, Prometheus node-exporter, and Loki canary will still be present afterwards.
`cluster-stop` and `cluster-start` remain as compatibility aliases.

```bash
flux get kustomizations -A
flux get helmreleases -A
kubectl get pods -A
```

## Bootstrap SOPS decryption in-cluster

```bash
make sops-age-key
make render-sops-secrets ENV=dev
make encrypt-secrets ENV=dev
make sops-bootstrap-cluster
```

## Remove only the cluster

```bash
make cluster-remove TOPOLOGY=local
```

## Teardown cluster and infrastructure

```bash
make environment-destroy TOPOLOGY=local TF_BIN=tofu
```
