# Flux bootstrap targets

This project now installs Flux with Flux Operator and bootstraps the controllers with a `FluxInstance`.

Pinned versions in the repository bootstrap flow:

- Flux Operator `0.45.1`
- Flux `2.8.3`

This project supports two topologies:

## 1) Local clusters (kind/minikube/k3d)

```bash
make install-flux-local
```

## 2) Non-local/shared clusters (dev/test/prod)

```bash
make install-flux
```

To target a specific kube-context:

```bash
make install-flux KUBE_CONTEXT=dev-cluster
```

## Target intent

- `install-flux-local`: local bootstrap convenience target.
- `install-flux`: topology-neutral target, with optional explicit context.
- `bootstrap-flux-instance`: applies the operator-managed `FluxInstance`.
- `bootstrap-flux-git`: compatibility alias for `bootstrap-flux-instance`.

`make bootstrap-flux-instance` renders the tracked cluster path under `flux/generated/clusters/<cluster-id>/`, then applies [`bootstrap/flux-operator/flux-instance.yaml.tmpl`](../bootstrap/flux-operator/flux-instance.yaml.tmpl) with:

- `GIT_REPO_URL` from `.env` or CI environment variables
- `GIT_BRANCH` from `.env` or CI environment variables
- `FLUX_INSTANCE_SYNC_PATH` defaulting to `./flux/generated/clusters/<cluster-id>`
- pinned `FLUX_OPERATOR_VERSION` and `FLUX_VERSION`

After `make bootstrap-flux-instance`, this repository reconciles through the staged root:

- `platform-bootstrap`
- `platform-infrastructure`
- `platform-applications`

For local testing of the built-in Flux Operator web UI:

```bash
make open-flux-operator-ui
make check-flux-operator-ui
```

That port-forwards `svc/flux-operator` to `http://localhost:9080`.

For operational checks, prefer `flux get kustomizations -A` over watching only the parent `platform` object.
