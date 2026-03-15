# Terraform in this repository

Terraform is **kept intentionally** in this project, but it has a specific role:

1. define the deployment topology
2. generate Ansible inventories and topology-specific values
3. optionally provision external dependencies such as DNS or router/firewall rules

For pre-existing physical hosts, Terraform does **not** install Kubernetes by itself.
That remains the responsibility of Ansible.

## Topologies

- `local`
- `minipc`
- `hybrid`
- `hybrid-remote`

## Generated artifacts

Each topology generates:

- `ansible/generated/<topology>.ini`
- `flux/generated/<topology>/metallb-values.yaml`
- `flux/generated/<topology>/node-labels.env`

## Optional modules

- `modules/cloudflare-dns`
- `modules/inventory-generator`
