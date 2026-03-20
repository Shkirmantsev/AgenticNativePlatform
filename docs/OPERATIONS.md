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
- `flux/generated/<topology>/topology-values.yaml` is informational metadata for operators and is not applied to Kubernetes

Validate generated manifests with:

```bash
kubectl kustomize flux/generated/local
kubectl kustomize flux/generated/clusters/local-dev-none-external
```

## GitHub workspace topology

`github-workspace` is the Docker / `k3d` based developer topology.

Use it for:

- GitHub workspaces / Codespaces,
- ephemeral development environments,
- local testing where MetalLB is not needed.

Behavior differences:

- `cluster-up-github-workspace` uses `k3d`,
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

It then scales Deployments and StatefulSets to zero in the configured platform namespaces.
It intentionally does not scale `metallb-system`; the MetalLB controller serves a validating webhook, and leaving it at `0` endpoints blocks later `IPAddressPool` reconciliation.
It also does not stop system namespaces or DaemonSets, so pods such as `flux-system`, `kube-system`, `cert-manager`, `istio-cni`, `ztunnel`, Prometheus node-exporter, and Loki canary will remain running by design.

Resume the platform and let Flux restore desired state:

```bash
make cluster-resume
make cluster-status
```

`cluster-resume` resumes the source, HelmReleases, and staged Kustomizations, reconciles `platform-bootstrap` first, then force-reconciles all existing HelmReleases in `flux-system` before waiting on `platform-infrastructure`, `platform-applications`, and `platform`.
That ordering reduces false "stuck" waits after `cluster-pause` because Helm-managed Deployments are driven back to their desired replica counts before the staged Flux roots wait on readiness.
`cluster-stop` and `cluster-start` remain as compatibility aliases for the previous names.

`make reconcile` follows the same staged idea without the suspend/resume step:

1. reconcile Git source
2. reconcile `platform-bootstrap`
3. force-reconcile HelmReleases
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

Close them:

```bash
make close-research-access
```

That exposes:

- `http://localhost:8080` for the kagent UI
- `http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json` for the sample A2A card
- `http://localhost:15000/v1/models` for AgentGateway
- `http://localhost:4000/v1/models` for LiteLLM
- `http://localhost:3000` for Grafana
- `http://localhost:9090` for Prometheus
- `http://localhost:6333/dashboard` for Qdrant

If a target still does not come up, check the actual failure mode:

- `Service ... has no ready endpoints` means the workload behind it is not running yet
- `unable to listen on any of the requested ports` means the localhost port is already occupied on the workstation

The access targets accept local port overrides, for example:

```bash
make open-litellm LITELLM_LOCAL_PORT=14000
```

LiteLLM itself requires `Authorization: Bearer <LITELLM_MASTER_KEY>`. If your `.env` has not overridden it yet, the first-bootstrap default is still `change-me`.

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

After importing, keep the same image tag in:

```bash
make flux-values TOPOLOGY=local ECHO_MCP_IMAGE=ghcr.io/<your-user>/echo-mcp:0.1.0
make render-cluster-root TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false
```

The concrete sample image is injected through generated Flux inputs from `ECHO_MCP_IMAGE`. The component manifests keep a neutral placeholder image so the repo does not hard-code a user-specific tag.

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
