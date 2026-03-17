# ADR-0005: Separate Terraform inputs from `.env` and keep local Helm charts for platform glue

## Status
Accepted

## Context
Earlier revisions mixed `.env` expectations with Terraform without actually wiring Terraform inputs to those values. The repository also depended heavily on Flux `HelmRelease` resources but did not make the local glue layer visible as Helm templates.

## Decision
- Terraform inputs are provided through topology-specific `terraform.tfvars` files generated from `.env` by helper scripts.
- `.env` remains the operator-facing source for Make targets, helper scripts, and secret rendering.
- Terraform generates inventory, MetalLB values, and LM Studio endpoint artifacts.
- Local Helm charts are kept for LiteLLM configuration, external service wiring, optional runtime templates, and sample kagent resources.

## Consequences
- Host IPs and LM Studio wiring are explicit and topology-specific.
- The repository exposes both upstream Helm-managed platform components and local Helm templates for the platform glue layer.
- Runtime-specific packaging stays visible and reviewable in Git instead of being hidden inside ad-hoc scripts.
