# ADR 0007: GitOps Repo and Secrets Modes

## Status

Accepted

## Decision

- Keep cluster sync roots committed under `clusters/<topology>-<env>/`.
- Keep shared manifests committed under `infrastructure/` and `apps/`.
- Keep non-secret values committed under `values/`.
- Keep encrypted GitOps secrets under `secrets/<topology>/`.
- Bootstrap Flux with Flux Operator and a committed cluster-specific `FluxInstance` template.
- Source `FluxInstance.spec.sync.url`, `ref`, and `path` from `.env` or CI/CD environment variables.
- Stage reconciliation as `platform-infrastructure`, `platform-secrets`, and `platform-applications`.

## Consequences

- Secrets can stay out of Git during bootstrap through `.generated/secrets/<env>/`.
- The repo structure is compatible with a later OCI-based Gitless Flux migration.
