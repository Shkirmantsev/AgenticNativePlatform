# Terraform in this repository

Terraform is **kept intentionally** in this project, but it has a specific role:

1. define the deployment topology
2. generate Ansible inventories and topology-specific values
3. optionally provision external dependencies such as DNS or router/firewall rules

For pre-existing physical hosts, Terraform does **not** install Kubernetes by itself.
That remains the responsibility of Ansible.

## Topologies

- `local`
- `github-workspace`
- `minipc`
- `hybrid`
- `hybrid-remote`

## Generated artifacts

Each topology generates:

- `ansible/generated/<topology>.ini`
- `flux/generated/<topology>/kustomization.yaml`
- `flux/generated/<topology>/litellm-values-configmap.yaml`
- `flux/generated/<topology>/tei-values-configmap.yaml`
- `flux/generated/<topology>/ollama-values-configmap.yaml`
- `flux/generated/<topology>/vllm-values-configmap.yaml`
- `flux/generated/<topology>/echo-mcp-values-configmap.yaml`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/...`
- `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/bootstrap-flux/`
- optional Flux-managed child roots under `flux/generated/clusters/<topology>-<env>-<runtime>-<secrets-mode>/samples-echo-mcp/`

Host-based topologies (`local`, `minipc`, `hybrid`, `hybrid-remote`) additionally generate:

- `flux/generated/<topology>/metallb-values.yaml`
- `flux/generated/<topology>/topology-values.yaml`
- `flux/generated/<topology>/lmstudio-endpoint.yaml`
- `flux/generated/<topology>/lmstudio-values-configmap.yaml`

`github-workspace` additionally generates:

- `.generated/k3d/github-workspace.yaml`

## Profile composition

The Flux manifest generator now renders staged roots through explicit profiles:

- `platform-profile-full`
- `platform-profile-workspace`
- `platform-profile-fast`
- `platform-profile-fast-serving`
- `platform-profile-fast-context`

Leave `platform_profile` unset to use the topology default, or set it explicitly through `TF_VAR_platform_profile` or `PLATFORM_PROFILE` in the repo scripts and `make` targets.
For `github-workspace`, the default `platform-profile-workspace` now composes the lighter `platform-profile-fast-serving` stack.

## Optional modules

- `modules/cloudflare-dns`
- `modules/flux-manifest-generator`
- `modules/inventory-generator`
