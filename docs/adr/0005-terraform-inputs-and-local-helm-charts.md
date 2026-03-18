# ADR-0005: Separate Terraform inputs from `.env` and keep local Helm charts for platform glue

## Status
Accepted

## Context
Earlier revisions mixed `.env` expectations with Terraform without actually wiring Terraform inputs to those values. The repository also depended heavily on Flux `HelmRelease` resources but did not make the local glue layer visible as Helm templates.

## Decision
- Terraform inputs are provided through topology-specific `terraform.tfvars` or generated `terraform.auto.tfvars` files.
- `.env` is reserved for Make and helper scripts.
- Terraform generates inventory, MetalLB values, and LM Studio endpoint artifacts.
- Local Helm charts are added for LiteLLM configuration, external service wiring, optional runtime templates, and demo flows.
- Flux `HelmRelease` resources that point at repo-local charts under `./charts/...` use `chart.spec.reconcileStrategy: Revision` so chart file changes rebuild packaged chart artifacts without requiring a `Chart.yaml` version bump during iterative development.
- Repo-local chart templates must not emit raw Flux-packaged `Chart.Version` values into Kubernetes labels, and images that default from `Chart.Version` should be pinned explicitly when upstream registries do not publish build-metadata tags.

## Consequences
- Host IPs and LM Studio wiring are now explicit and topology-specific.
- The repository exposes both upstream Helm-managed platform components and local Helm templates for the platform glue layer.
- Plaintext generated files stay local, while encrypted GitOps-safe outputs can be committed.
- Local chart debugging is less surprising because a Git revision change is enough to trigger a rebuilt Flux `HelmChart` artifact.
- Local chart authors need to treat Flux-added build metadata as packaging information, not as a safe default Kubernetes label value.
