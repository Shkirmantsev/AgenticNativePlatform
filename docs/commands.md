# Commands

## Bootstrap

```bash
cp .env.example .env
make run-cluster-from-scratch
```

Defaults:

```bash
TOPOLOGY=local ENV=dev RUNTIME=none SECRETS_MODE=external LMSTUDIO_ENABLED=false IAC_TOOL=tofu
```

## Cluster removal

Meanings:

- `cluster-pause`: reversible workload suspension; keep the cluster running
- `remove-cluster-only`: delete the cluster only; keep Terraform/OpenTofu infrastructure and repo-generated assets
- `destroy-cluster-and-infra`: delete the cluster and also destroy Terraform/OpenTofu-managed infrastructure
- `cluster-remove`: compatibility alias for `remove-cluster-only`
- `environment-destroy`: compatibility alias for `destroy-cluster-and-infra`

```bash
make remove-cluster-only TOPOLOGY=local
make cluster-remove TOPOLOGY=local
make destroy-cluster-and-infra TOPOLOGY=local TF_BIN=tofu
make environment-destroy TOPOLOGY=local TF_BIN=tofu
```

## Terraform and inventory

```bash
make render-terraform-tfvars TOPOLOGY=local
make terraform-init TOPOLOGY=local
make terraform-apply TOPOLOGY=local
```

## Host bootstrap

```bash
make bootstrap-hosts TOPOLOGY=local
make install-k3s-server TOPOLOGY=local
make join-workers TOPOLOGY=hybrid
make kubeconfig TOPOLOGY=local
```

## Flux

```bash
make install-flux-local
make bootstrap-flux-instance TOPOLOGY=local ENV=dev
make reconcile
make verify
make cluster-status
```

## Secrets

```bash
make apply-plaintext-secrets TOPOLOGY=local ENV=dev
make render-sops-secrets TOPOLOGY=local ENV=dev
make encrypt-secrets TOPOLOGY=local ENV=dev
make decrypt-secrets TOPOLOGY=local ENV=dev
make sops-bootstrap-cluster
```

## Validation

```bash
make validate-config
make check-flux-stages
kubectl kustomize clusters/local-dev
kubectl kustomize clusters/local-dev/infrastructure
kubectl kustomize clusters/local-dev/apps
kubectl kustomize clusters/local-dev/secrets
```

## Local UI and APIs

```bash
make open-research-access
make open-agentgateway-admin-ui
make open-phoenix
make open-agentregistry-inventory
make check-kagent-ui
make check-agentgateway
make check-agentgateway-openai
make check-litellm
make check-phoenix
make check-agentregistry-inventory
make open-flux-operator-ui
make check-flux-operator-ui
```
