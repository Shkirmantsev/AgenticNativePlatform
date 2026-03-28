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

## Consequences

- Terraform/OpenTofu no longer owns GitOps root generation
- the repository is ready for later OCI-based packaging of independent trees
