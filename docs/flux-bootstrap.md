# Flux Bootstrap

Flux is installed with Flux Operator and configured with a committed cluster-specific `FluxInstance` template under:

- `clusters/<topology>-<env>/flux-system/flux-instance.yaml`

Pinned versions:

- Flux Operator `0.45.1`
- Flux `2.8.3`

## Install

```bash
make install-flux-local
```

or:

```bash
make install-flux KUBE_CONTEXT=<context>
```

## Bootstrap the sync path

```bash
make bootstrap-flux-instance TOPOLOGY=local ENV=dev
```

Inputs:

- `GIT_REPO_URL`
- `GIT_BRANCH`
- `FLUX_INSTANCE_SYNC_PATH`

Default sync path:

```bash
./clusters/local-dev/external
```

## Local UI access

```bash
make open-flux-operator-ui
make check-flux-operator-ui
```

This opens the built-in Flux Operator UI on `http://localhost:9080`.
