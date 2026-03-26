# Operations

## Committed GitOps state

Commit:

- `bootstrap/`
- `clusters/`
- `infrastructure/`
- `apps/`
- `charts/`
- `values/`
- `secrets/<topology>/` when using SOPS

Do not commit:

- `.env`
- `.generated/`
- `.kube/generated/`
- `terraform/environments/*/terraform.auto.tfvars`
- `.sops/`

## Static validation

```bash
kubectl kustomize clusters/local-dev
kubectl kustomize clusters/local-dev/infrastructure
kubectl kustomize clusters/local-dev/apps
kubectl kustomize clusters/local-dev/secrets
git diff --check
```

## Pause and resume

Pause:

```bash
make cluster-pause
```

Resume:

```bash
make cluster-resume
make cluster-status
make diagnose-runtime-state
```

The pause/resume flow now works against:

- `platform-infrastructure`
- `platform-secrets`
- `platform-applications`

## Secrets

Plaintext bootstrap:

```bash
make apply-plaintext-secrets TOPOLOGY=local ENV=dev
```

SOPS flow:

```bash
make sops-age-key
make render-sops-secrets TOPOLOGY=local ENV=dev
make encrypt-secrets TOPOLOGY=local ENV=dev
make sops-bootstrap-cluster
```

Committed encrypted files live under `secrets/<topology>/`.

## Operator access

```bash
make open-research-access
make close-research-access
```

Useful endpoints:

- `http://localhost:8080` kagent UI
- `http://localhost:8083/api/a2a/kagent/finnhub-agent/.well-known/agent.json` finnhub-agent card
- `http://localhost:8083/api/a2a/kagent/team-lead-agent-assist/.well-known/agent.json` team-lead-agent-assist card
- `http://localhost:15000/v1/models` AgentGateway
- `http://localhost:15000/api/a2a/kagent/finnhub-agent/.well-known/agent.json` finnhub-agent card through AgentGateway
- `http://localhost:15000/api/a2a/kagent/team-lead-agent-assist/.well-known/agent.json` team-lead-agent-assist card through AgentGateway
- `http://localhost:4000/v1/models` LiteLLM
- `http://localhost:3000` Grafana
- `http://localhost:9090` Prometheus
- `http://localhost:6333/dashboard` Qdrant
- `http://localhost:9080` Flux Operator UI
