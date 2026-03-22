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

Host-based topologies (`local`, `minipc`, `hybrid`, `hybrid-remote`) additionally generate:

- `flux/generated/<topology>/metallb-values.yaml`
- `flux/generated/<topology>/topology-values.yaml`
- `flux/generated/<topology>/lmstudio-endpoint.yaml`
- `flux/generated/<topology>/lmstudio-values-configmap.yaml`

`github-workspace` additionally generates:

- `.generated/k3d/github-workspace.yaml`

## Optional modules

- `modules/cloudflare-dns`
- `modules/flux-manifest-generator`
- `modules/inventory-generator`
