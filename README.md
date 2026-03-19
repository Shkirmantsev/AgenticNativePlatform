# AgenticNativePlatform

Cloud native AI agentic enterprise platform, based on Kubernetes (education project).

## Current repository status

This repository currently contains a minimal bootstrap for running the platform tooling in both local environments and GitHub Codespaces.

## GitHub Codespaces quick start

1. Open this repository in a new Codespace.
2. Wait for the `postCreateCommand` to finish (`scripts/bootstrap.sh`).
3. Validate the runtime toolchain:

```bash
bash scripts/validate-environment.sh
```

## Local development quick start

Run the same bootstrap and validation scripts:

```bash
bash scripts/bootstrap.sh
bash scripts/validate-environment.sh
```

## What gets installed

The bootstrap script ensures these tools are present:

- `docker`
- `kubectl`
- `helm`
- `kind`
- `kustomize`
- `flux`

These are the baseline dependencies needed to run a Kubernetes-oriented topology consistently on developer machines and in Codespaces.
