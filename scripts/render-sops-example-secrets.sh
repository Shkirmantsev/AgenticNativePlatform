#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${ENV:-dev}"

cat <<'MSG'
Use your own age recipient and real SOPS locally to replace the placeholder examples, for example:

  make render-sops-secrets ENV=${ENVIRONMENT}
  make encrypt-secrets ENV=${ENVIRONMENT}

The generated files are:

  flux/secrets/${ENVIRONMENT}/litellm-provider-secrets.sops.yaml
  flux/secrets/${ENVIRONMENT}/kagent-agentgateway.sops.yaml

Then bootstrap Flux with:

  make sops-bootstrap-cluster
  make bootstrap-flux-git TOPOLOGY=local ENV=${ENVIRONMENT} RUNTIME=none SECRETS_MODE=sops
MSG
