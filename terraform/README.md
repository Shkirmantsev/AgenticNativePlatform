# Terraform

Terraform/OpenTofu is limited to infra-like concerns:

- topology and inventory generation
- host facts
- `k3d` config generation

It no longer generates Flux cluster roots.

Tracked outputs written by Terraform:

- `ansible/generated/<topology>.ini`
- `clusters/<topology>-<env>/topology-values.yaml`
- `clusters/<topology>-<env>/infrastructure/generated-lmstudio-endpoint.yaml`
- `clusters/<topology>-<env>/infrastructure/generated-metallb-resources.yaml`
- `values/<topology>/lmstudio-external.yaml`
