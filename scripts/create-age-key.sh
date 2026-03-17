#!/usr/bin/env bash
set -euo pipefail
mkdir -p .sops
if ! command -v age-keygen >/dev/null 2>&1; then
  echo "age-keygen is not installed. Install age first or run make tools-install-local." >&2
  exit 1
fi
if [ -f .sops/age.agekey ]; then
  echo ".sops/age.agekey already exists"
else
  age-keygen -o .sops/age.agekey
  grep '^# public key:' .sops/age.agekey | sed 's/# public key: //' > .sops/age.pub
  printf 'Created %s and %s
' .sops/age.agekey .sops/age.pub
fi
if [[ -f .sops/age.pub ]]; then
  pub=$(cat .sops/age.pub)
  cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: flux/secrets/.*\.ya?ml
    age: ${pub}
EOF
  echo "Updated .sops.yaml with recipient ${pub}"
fi
