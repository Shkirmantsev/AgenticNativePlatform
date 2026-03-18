# ADR-0007: One GitOps repository with external and SOPS secrets modes

## Status
Accepted

## Context
The platform must be easy to start in a home-lab environment, but it must also support proper encrypted GitOps later.

## Decision
- Use one repository for charts, Flux manifests, Terraform/OpenTofu, Ansible, docs, and helper scripts.
- Flux reads the remote URL of this same repository after the operator pushes it.
- Commit generated GitOps inputs that Flux must read remotely, including `flux/generated/<topology>/` and `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`.
- Render the cluster root as staged Flux `Kustomization` resources (`platform-bootstrap`, `platform-infrastructure`, `platform-applications`) so CRD-providing charts reconcile before dependent custom resources.
- Support two practical secret modes:
  - `external`: secrets rendered from `.env` into `.generated/secrets/<env>/` and applied directly to the cluster
  - `sops`: plaintext rendered locally, then encrypted into committed `flux/secrets/<env>/*.sops.yaml`
- Do not commit plaintext secrets.
- Do not commit local `terraform.auto.tfvars` files.

## Consequences
- The first bootstrap stays simple.
- Production-like encrypted GitOps remains available without redesigning the repo.
- Operators have one source of truth for manifests, charts, and docs.
- Stop/start flows must account for the staged child Kustomizations, not only the top-level `platform` object.
