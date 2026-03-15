# ADR-0005: Separate Terraform inputs from `.env` and keep local Helm charts for platform glue

## Status
Accepted

## Context
Earlier revisions mixed `.env` expectations with Terraform without actually wiring Terraform inputs to those values. The repository also depended heavily on Flux `HelmRelease` resources but did not make the local glue layer visible as Helm templates.

## Decision
- Terraform inputs are provided through topology-specific `terraform.tfvars` files.
- `.env` is reserved for Make and helper scripts.
- Terraform generates inventory, MetalLB values, and LM Studio endpoint artifacts.
- Local Helm charts are added for LiteLLM configuration, external service wiring, optional runtime templates, and standalone demo flows.

## Consequences
- Host IPs and LM Studio wiring are now explicit and topology-specific.
- The repository exposes both upstream Helm-managed platform components and local Helm templates for the platform glue layer.
