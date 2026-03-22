# Flux bootstrap targets

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

`make bootstrap-flux-git` now applies generated manifests from `flux/generated/clusters/<cluster-id>/bootstrap-flux/`, so the GitRepository and root Flux Kustomization are rendered declaratively by OpenTofu before the thin shell wrapper applies them.

After `make bootstrap-flux-git`, this repository reconciles through the staged root:

- `platform-bootstrap`
- `platform-infrastructure`
- `platform-applications`

For operational checks, prefer `flux get kustomizations -A` over watching only the parent `platform` object.
