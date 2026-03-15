# ADR-0002: Secrets management

## Status
Accepted

## Context
We must store secrets in Git in encrypted form and keep the workflow declarative and GitOps-friendly.

## Decision
Use **SOPS + age** as the default secrets mechanism.
Optional Vault integration stays available as a future overlay, but not as the default path.

## Why
- Works naturally with Flux.
- Easy to review in Git.
- No mandatory in-cluster secret control plane for the first iteration.
- Good fit for dev/stage/prod overlays.

## Consequences
- Operators must manage the age private key securely.
- Secret rotation requires Git updates and re-encryption.
