# ADR 0001: Platform Architecture

## Status

Accepted

## Decision

The platform uses:

- Flux Operator for Flux lifecycle management
- static cluster roots under `clusters/`
- shared Git-authored manifests under `infrastructure/` and `apps/`
- repo-local and vendored Helm charts under `charts/`
- non-secret configuration under `values/`
- topology-scoped SOPS roots under `secrets/`
- an internal Agent Registry Inventory control plane under `agentregistry` for cataloging kagent/KMCP runtime resources
- a local-only workstation OCI pull-through cache that `bootstrap-hosts` installs before `k3s` starts so repeated local rebuilds can reuse image layers

## Architecture Summary

The current repository architecture has three layers:

1. Host/bootstrap layer
   - OpenTofu/Terraform renders topology-specific inventory and generated inputs.
   - Ansible bootstraps the host, installs the local OCI cache for `TOPOLOGY=local`, and installs `k3s`.
2. GitOps source layer
   - committed cluster roots under `clusters/<topology>-<env>/`
   - shared manifests under `infrastructure/`, `apps/`, `charts/`, `values/`, and `secrets/`
3. Cluster runtime layer
   - Flux Operator manages the Flux controllers through a committed `FluxInstance`
   - staged Flux `Kustomization` resources fan out into infrastructure, secrets, and applications

The stage ordering is intentionally:

- `platform-infrastructure`: controllers, CRDs, namespaces, and shared platform releases
- `platform-secrets`: runtime secrets and decrypted SOPS content
- `platform-applications`: application-level resources that need both the platform and the secret stage

`platform-secrets` does not wait for `platform-infrastructure` readiness because several infrastructure Helm releases consume secrets during install. `platform-applications` waits for both stages explicitly.

### Local Topology Path

For `TOPOLOGY=local`, the workstation path is:

```text
bootstrap-hosts
  -> install host-level OCI pull-through cache
  -> install-k3s-server
  -> render /etc/rancher/k3s/registries.yaml
  -> repeated local cluster rebuilds reuse cached image layers
```

## Consequences

- Terraform/OpenTofu no longer owns GitOps root generation
- the repository is ready for later OCI-based packaging of independent trees
- local `cluster-remove` is faster after the first pull because cached layers survive outside the `k3s` data dir
- full `environment-destroy` still removes the local cache by default so the workstation can return to a clean state
