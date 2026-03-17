# ADR-0007 Single GitOps repo and staged secret handling

## Status
Accepted

## Context
The platform needs a clean first-start path without forcing secret encryption immediately, while preserving a final production path with GitOps-managed encrypted secrets.

## Decision
Use one Git repository for charts, Flux manifests, Terraform, Ansible, docs, and generated Flux values.

Use three secret handling modes:
- `external`: secrets created directly in the cluster from `.env` and not stored in Git
- `sops`: encrypted secrets committed to `flux/secrets/<env>/`
- `plaintext`: disposable lab mode only

## Consequences
- First startup is easier: no encryption is required.
- Final GitOps remains clean: SOPS + age + Flux decryption in the same repository.
- Flux always points to the remote URL of this same repository and reads the generated cluster root path from that remote.
