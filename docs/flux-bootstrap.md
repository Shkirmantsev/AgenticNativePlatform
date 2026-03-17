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
