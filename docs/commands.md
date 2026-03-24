# Commands

## Bootstrap

```bash
cp .env.example .env
make run-cluster-from-scratch TOPOLOGY=local
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
make check-kagent-ui
make check-agentgateway
make check-agentgateway-openai
make check-litellm
make open-flux-operator-ui
make check-flux-operator-ui
```
