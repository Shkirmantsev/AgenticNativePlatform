# ADR-0007: One GitOps repository with external and SOPS secrets modes

## Status
Accepted

## Context
The platform must be easy to start in a home-lab environment, but it must also support proper encrypted GitOps later.

## Decision
- Use one repository for charts, Flux manifests, Terraform/OpenTofu, Ansible, docs, and helper scripts.
- Bootstrap Flux with Flux Operator and manage the controller sync configuration through a committed `FluxInstance`.
- Source `FluxInstance.spec.sync.url`, `ref`, and `path` from operator inputs such as `.env` for local runs or CI/CD environment variables for pipeline-driven runs.
- Flux reads the remote URL of this same repository rather than the local worktree.
- Commit generated GitOps inputs that Flux must read remotely, including `flux/generated/<topology>/` and `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/`.
- Render the cluster root as staged Flux `Kustomization` resources (`platform-bootstrap`, `platform-infrastructure`, `platform-applications`) so CRD-providing charts reconcile before dependent custom resources.
- Support two practical secret modes:
  - `external`: secrets rendered from `.env` into `.generated/secrets/<env>/` and applied directly to the cluster
  - `sops`: plaintext rendered locally, then encrypted into committed `flux/secrets/<env>/*.sops.yaml`
- Do not commit plaintext secrets.
- Do not commit local `terraform.auto.tfvars` files.

## Consequences
- The first bootstrap stays simple.
- Flux lifecycle management is declarative and version-pinned without relying on `flux install` plus separately rendered bootstrap objects.
- Production-like encrypted GitOps remains available without redesigning the repo.
- Operators have one source of truth for manifests, charts, and docs.
- Stop/start flows must account for the staged child Kustomizations, not only the top-level `platform` object.
- If stop/start works by suspending Flux objects and scaling workloads to zero, restart must also force HelmRelease reconciliation or Helm-managed Deployments such as `istiod` can remain at `0/0` even though the release is marked ready.
