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
- the `Makefile` exports `KUBECONFIG` to that path by default
- `flux` and `kubectl` targets that talk to the cluster expect that file to exist
- stale files under `ansible/playbooks/.kube/` are old artifacts and can be deleted

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

`make sops-bootstrap-cluster` requires kubeconfig to be exported first, so run `make kubeconfig TOPOLOGY=<topology>` before it if needed.

## Start, stop, and teardown

Pause the platform without removing the cluster:

```bash
make cluster-stop
```

`cluster-stop` suspends:

- `GitRepository/flux-system/platform`
- staged child Kustomizations such as `platform-bootstrap`, `platform-infrastructure`, `platform-applications`
- all HelmReleases in `flux-system`

It then scales Deployments and StatefulSets to zero in the configured platform namespaces.

Resume the platform and let Flux restore desired state:

```bash
make cluster-start
```

`cluster-start` resumes the source, HelmReleases, and staged Kustomizations, then reconciles them in order.
It also force-reconciles all existing HelmReleases in `flux-system` so workloads scaled down by `cluster-stop` are pushed back to their desired replica counts instead of remaining at zero because the release looked otherwise in-sync.

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
Use the `make` targets directly instead of `sudo make`; the embedded Ansible tasks already run with privilege escalation.

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
