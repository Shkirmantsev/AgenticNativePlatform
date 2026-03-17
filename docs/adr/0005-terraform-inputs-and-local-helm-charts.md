# ADR-0005: Separate local Terraform inputs from `.env` and keep local Helm charts for platform glue

## Status
Accepted

## Context
Earlier revisions mixed `.env` expectations with Terraform without actually wiring Terraform inputs to those values. The repository also depended heavily on Flux `HelmRelease` resources but did not make the local glue layer visible as Helm templates.

## Decision
- `.env` remains the human-friendly operator input file.
- A local helper script renders `.env` into uncommitted `terraform.auto.tfvars` files under `terraform/environments/<topology>/`.
- Terraform/OpenTofu generates:
  - the Ansible inventory
  - the LM Studio endpoint values
  - the MetalLB address pool manifest
  - topology metadata under `flux/generated/<topology>/`
- Local Helm charts are kept for runtime-specific components and external-service glue:
  - `litellm-proxy`
  - `lmstudio-external`
  - `ollama-runtime`
  - `vllm-cpu`
  - `tei-embeddings`
  - `kagent-agents`
- `charts/ai-runtimes` is retained as a demo/manual packaging chart, not as the default production path.

## Consequences
- Host IPs and LM Studio wiring are explicit and topology-specific.
- Terraform/OpenTofu does not consume `.env` directly.
- Sensitive local Terraform inputs are not committed to Git.
- The repository exposes both upstream Helm-managed platform components and local Helm templates for the platform glue layer.
