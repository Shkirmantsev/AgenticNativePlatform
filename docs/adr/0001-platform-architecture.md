# ADR 0001: Platform Architecture

## Status

Accepted

## Decision

The platform uses:

- Flux Operator for Flux lifecycle management
- static cluster roots under `clusters/`
- shared Git-authored manifests under `infrastructure/` and `apps/`
- non-secret configuration under `values/`
- topology-scoped SOPS roots under `secrets/`

## Consequences

- Terraform/OpenTofu no longer owns GitOps root generation
- the repository is ready for later OCI-based packaging of independent trees
