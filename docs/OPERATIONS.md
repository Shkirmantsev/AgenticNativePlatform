# Operations

## What Ansible does

Ansible is used for:
- installing local operator tools on the workstation
- preparing hosts for k3s
- installing the k3s server
- joining worker nodes
- labeling runtime-capable worker nodes
- exporting kubeconfig
- uninstalling k3s

## What scripts do

Scripts are kept for local repository operations that are not natural Ansible tasks:
- rendering `terraform.auto.tfvars` from `.env`
- rendering Flux ConfigMaps and cluster roots
- rendering external plaintext secrets
- converting plaintext secrets into encrypted SOPS files
- bootstrapping Flux Git sources and the Flux SOPS secret

## What is committed to Git

Commit:
- `charts/`
- `flux/components/`
- `flux/overlays/`
- `flux/generated/<topology>/`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`
- encrypted `flux/secrets/<env>/*.sops.yaml` only when using SOPS mode

Do not commit:
- `.env`
- `terraform/environments/*/terraform.auto.tfvars`
- `.generated/`
- `.kube/generated/`
- `ansible/generated/`
- `.sops/`

## Local kubeconfig behavior

- `make kubeconfig` writes the usable kubeconfig to `.kube/generated/current.yaml`
- repo `make` targets bind that kubeconfig explicitly
- `flux` and `kubectl` targets that talk to the cluster expect that file to exist
- stale files under `ansible/playbooks/.kube/` are old artifacts and can be deleted

## One-command bootstrap

For the standard first-run path, use:

```bash
cp .env.example .env
# edit .env for your machine and credentials
make run-cluster-from-scratch
```

That target orchestrates the existing building blocks in order:

1. install local operator tools
2. provision the selected topology inputs
3. render tracked Flux inputs and verify they are already committed
4. continue host bootstrap and kubeconfig export
5. install Flux
6. apply first-pass secrets
7. bootstrap the Flux Git objects
8. reconcile staged Kustomizations and HelmReleases
9. print cluster status

It intentionally stops after the topology render step if tracked generated manifests under `flux/generated/...` changed locally, because Flux reads the remote Git branch rather than your local working tree.
`make bootstrap-flux-git` also refuses to continue when the Git worktree is dirty or when local `HEAD` does not match `GIT_REPO_URL@GIT_BRANCH`, because the cluster follows the remote branch, not unpublished local edits.

Topology distinction:

- `local` uses host-level `k3s` with Terraform/OpenTofu + Ansible provisioning
- `github-workspace` uses `k3d` and skips host provisioning

If `k9s` looks empty, it is usually reading the wrong kubeconfig or a narrowed namespace view. Prefer:

```bash
make k9s-local
```

## Generated Flux artifacts

- `flux/generated/<topology>/kustomization.yaml` is the generated topology input root
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/kustomization.yaml` is the generated cluster root used by bootstrap scripts
- the generated cluster root fans out into staged Flux `Kustomization` resources so CRDs and charts install before dependent custom resources
- the staged infra/apps roots render through `flux/components/profiles/`, which compose bundle Kustomizations under `flux/components/bundles/`
- optional apply paths such as `samples-echo-mcp/` and `weave-gitops/` are generated alongside the staged roots without entering the default bootstrap path
- `flux/generated/<topology>/topology-values.yaml` is informational metadata for operators and is not applied to Kubernetes

Validate generated manifests with:

```bash
kubectl kustomize flux/generated/local
kubectl kustomize flux/generated/clusters/local-dev-none-external
```

If you want a lighter local composition for faster iteration, override the generated profile explicitly:

```bash
make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external PLATFORM_PROFILE=platform-profile-fast
```

Default profile mapping stays conservative:

- host-based topologies default to `platform-profile-full`
- `github-workspace` defaults to `platform-profile-workspace`

## GitHub workspace topology

`github-workspace` is the Docker / `k3d` based developer topology.

Use it for:

- GitHub workspaces / Codespaces,
- ephemeral development environments,
- local testing where MetalLB is not needed.

Behavior differences:

- `cluster-up-github-workspace` uses `k3d`,
- the `k3d` cluster shape is rendered into `.generated/k3d/github-workspace.yaml` before creation,
- `cluster-remove` deletes the `k3d` cluster when `TOPOLOGY=github-workspace`,
- `environment-destroy` skips Terraform destroy for this topology,
- operator access should use port-forwarding instead of external LoadBalancer IPs.

## External secrets mode

Use `SECRETS_MODE=external` for the first bootstrap stage.

Secrets are rendered from `.env` into `.generated/secrets/<env>/` and applied directly to the cluster with:

```bash
make apply-plaintext-secrets ENV=dev
```

This keeps secrets out of Git while the platform is still being brought up.

## SOPS mode

Use `SECRETS_MODE=sops` once the basic platform works.

Flow:
1. create a local age key
2. render plaintext secret inputs under `.generated/secrets/<env>/`
3. encrypt them into committed `flux/secrets/<env>/`
4. create the Flux decryption secret in `flux-system`
5. switch the cluster root to `SECRETS_MODE=sops`

Commands:

```bash
make sops-age-key
make render-sops-secrets ENV=dev
make encrypt-secrets ENV=dev
make sops-bootstrap-cluster
```

`make sops-bootstrap-cluster` uses the repo kubeconfig automatically once `make kubeconfig TOPOLOGY=<topology>` has written `.kube/generated/current.yaml`.

## Pause, resume, and teardown

Pause the platform without removing the cluster:

```bash
make cluster-pause
```

`cluster-pause` suspends:

- `GitRepository/flux-system/platform`
- staged child Kustomizations such as `platform-bootstrap`, `platform-infrastructure`, `platform-applications`
- all HelmReleases in `flux-system`

It first snapshots the current Deployment and StatefulSet replica targets into `ConfigMap/flux-system/cluster-pause-state`, then scales the configured platform namespaces to zero.
It intentionally does not scale `metallb-system`; the MetalLB controller serves a validating webhook, and leaving it at `0` endpoints blocks later `IPAddressPool` reconciliation.
It also does not stop system namespaces or DaemonSets, so pods such as `flux-system`, `kube-system`, `cert-manager`, `istio-cni`, `ztunnel`, Prometheus node-exporter, and Loki canary will remain running by design.

Resume the platform and let Flux restore desired state:

```bash
make cluster-resume
make cluster-status
make diagnose-runtime-state
```

`cluster-resume` resumes the source, HelmReleases, and staged Kustomizations, reconciles `platform-bootstrap` first, restores the saved replica targets from `ConfigMap/flux-system/cluster-pause-state`, fans out HelmRelease reconcile annotations, and then waits on `platform-infrastructure`, `platform-applications`, and `platform`.
That ordering avoids a common failure mode after `cluster-pause`: direct `kubectl scale` changes `spec.replicas` field ownership and can leave HPA-managed Deployments such as `istiod` stuck at `ScalingDisabled` when replicas stay at `0`.
`cluster-stop` and `cluster-start` remain as compatibility aliases for the previous names.

If LiteLLM, PostgreSQL, Qdrant, Redis, or TEI appear to be missing after a pause or restart, treat that as a runtime-state problem first:

```bash
make diagnose-runtime-state
```

Those workloads live in the pause-sensitive namespaces `ai-gateway`, `ai-models`, and `context`, so stale `0` replicas usually explain the symptom better than a missing manifest does.

If the saved pause snapshot is missing or stale, recover those namespaces explicitly:

```bash
make recover-paused-workloads
```

`make reconcile` follows the same staged idea without the suspend/resume step:

1. reconcile Git source
2. reconcile `platform-bootstrap`
3. fan out HelmRelease reconcile annotations
4. wait on `platform-infrastructure`, `platform-applications`, and `platform`

Remove only the cluster and keep infrastructure:

```bash
make cluster-remove TOPOLOGY=local
```

Remove the cluster and Terraform/OpenTofu infrastructure together:

```bash
make environment-destroy TOPOLOGY=local TF_BIN=tofu
```

## Local access paths for operators

For local inspection from the workstation, use port-forwarding first. This does not require `kgateway`, MetalLB, or any external IP allocation.

Open the common access paths in the background:

```bash
make open-research-access
```

`make open-research-access` is best-effort: it tries all standard port-forwards, prints a summary table, and reports failures only after attempting every endpoint.

Close them:

```bash
make close-research-access
```

That exposes:

- `http://localhost:8080` for the kagent UI
- `http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json` for the sample A2A card
- `http://localhost:15000/v1/models` for the AgentGateway OpenAI-compatible API
- `http://localhost:15000/mcp/kagent-tools` for the bundled MCP route through AgentGateway
- `http://localhost:4000/health/readiness` for LiteLLM readiness
- `http://localhost:4000/v1/models` for the LiteLLM API
- `http://localhost:3000` for Grafana
- `http://localhost:9090` for Prometheus
- `http://localhost:6333/dashboard` for Qdrant

The AgentGateway and LiteLLM port-forwards expose API endpoints, not UI root pages.
`make open-agentgateway` checks only gateway/tunnel liveness now; use `make check-agentgateway-openai` or `make test-agentgateway-openai` for the backend-dependent `/v1/models` path.

Endpoint truth table:

| URL | Expected behavior |
| --- | --- |
| `http://localhost:15000/` | no root route is expected |
| `http://localhost:15000/v1/models` | AgentGateway OpenAI-compatible API |
| `http://localhost:15000/mcp/kagent-tools` | bundled MCP route through AgentGateway |
| `http://localhost:4000/health/readiness` | LiteLLM readiness endpoint |
| `http://localhost:4000/v1/models` | LiteLLM API |

If a target still does not come up, check the actual failure mode:

- `Service ... has no ready endpoints` means the workload behind it is not running yet
- `unable to listen on any of the requested ports` means the localhost port is already occupied on the workstation

The access targets accept local port overrides, for example:

```bash
make open-kagent-ui KAGENT_UI_LOCAL_PORT=18080
make open-kagent-a2a KAGENT_A2A_LOCAL_PORT=18083
make open-agentgateway AGENTGATEWAY_LOCAL_PORT=16000
make open-litellm LITELLM_LOCAL_PORT=14000
make open-grafana GRAFANA_LOCAL_PORT=13000
make open-prometheus PROMETHEUS_LOCAL_PORT=19090
make open-qdrant QDRANT_LOCAL_PORT=16333
```

LiteLLM itself requires `Authorization: Bearer <LITELLM_MASTER_KEY>`. If your `.env` has not overridden it yet, the first-bootstrap default is still `change-me`.

Use the explicit checks when validating local access:

```bash
make check-kagent-ui
make check-agentgateway
make check-agentgateway-openai
make check-litellm
make check-flux-stages
```

Use `kgateway` plus MetalLB or another bare-metal exposure method only when you need stable LAN-facing or externally reachable URLs.
On the default local topology, it is normal for Gateway resources to exist before they have an external `ADDRESS`; in that state, localhost port-forwarding remains the correct operator path.
When the gateway-facing Service `agentgateway-proxy` has a MetalLB IP, the external AgentGateway endpoint is:

```text
http://<metallb-ip>:8080/v1/models
```

## Local image import for optional sample workloads

Local Docker images are not automatically visible to `k3s`, because the cluster runs on containerd rather than the Docker daemon image store.

For the optional `echo-mcp` sample, you can avoid pushing to a registry by importing the built image into all `k3s` nodes:

```bash
make build-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0
make save-echo-mcp-image ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
make preimport-echo-mcp-image-tarball TOPOLOGY=local ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
```

Or use the shortcut:

```bash
make prepare-echo-mcp-image-local TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0 ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar
```

This only prepares the opt-in sample image. It does not add `/mcp/echo`, a default `RemoteMCPServer`, or an `echo-validation-agent` to the base platform path.

To deploy the sample server itself, render the generated optional bundle and apply it explicitly:

```bash
make flux-values TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0
make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
kubectl --kubeconfig .kube/generated/current.yaml apply -k flux/generated/clusters/local-dev-none-external/samples-echo-mcp
```

That opt-in path deploys only the sample `MCPServer`. It still does not create an AgentGateway `/mcp/echo` route or a validation agent.

## Optional Weave GitOps UI

The Weave GitOps dashboard is now a Flux-managed optional bundle.

Render the staged roots, apply the optional path, and use localhost access:

```bash
make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
kubectl --kubeconfig .kube/generated/current.yaml apply -k flux/generated/clusters/local-dev-none-external/weave-gitops
kubectl --kubeconfig .kube/generated/current.yaml -n flux-system port-forward svc/weave-gitops 19001:9001
```

Access the UI at `http://localhost:19001`.

The bundle is configured explicitly for local operator use:

- `ClusterIP` service only
- ingress disabled
- local admin user enabled

The bundled demo credentials are `admin` / `change-me`. Rotate the bcrypt hash in `flux/components/weave-gitops/release.yaml` before using anything except localhost-only access.

The import targets create `/var/lib/rancher/k3s/agent/images/` automatically when it is missing.
They also run `k3s ctr images import` immediately after copying the tarball so new image tags are available without waiting for a background import path.
Use the `make` targets directly instead of `sudo make`; the embedded Ansible tasks already run with privilege escalation and will prompt through `sudo` on a local workstation when needed.

On `TOPOLOGY=github-workspace`, `preimport-echo-mcp-image-tarball` loads the image into Docker first and then imports it into the `k3d` cluster instead of using the host `k3s` image directory.

Remove k3s from the current topology:

```bash
make uninstall-k3s TOPOLOGY=local
```

Destroy local Terraform/OpenTofu artifacts:

```bash
make terraform-destroy TOPOLOGY=local TF_BIN=tofu
```

## Known K3s-specific runtime detail

When using Istio CNI on K3s, the chart must target the K3s agent-managed CNI paths:

- `cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d`
- `cniBinDir=/var/lib/rancher/k3s/data/cni`
- `ambient.enabled=true` when the platform uses `ztunnel` and ambient-labeled namespaces

If `istio-cni` waits forever on an empty `/etc/cni/net.d`, the HelmRelease is using generic Kubernetes defaults instead of the K3s paths.
If `ztunnel` stays unready and logs that `/var/run/ztunnel/ztunnel.sock` is missing, `istio-cni` is running without ambient mode enabled.

## Known TEI CPU detail

The default `tei-embeddings` deployment uses the CPU Text Embeddings Inference image. For that path, prefer an ONNX-backed embedding model such as `onnx-models/all-MiniLM-L6-v2-onnx`.

If `tei-embeddings` downloads tokenizer files and then fails looking for `model.onnx`, the configured model does not ship the ONNX artifacts that this runtime expects.
