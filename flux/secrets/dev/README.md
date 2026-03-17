# dev secrets

Commit only encrypted `*.sops.yaml` secrets to this directory.

Do not commit plaintext secrets here. Generate plaintext locally into `.generated/secrets/dev/`, then run `make encrypt-secrets ENV=dev` to produce encrypted files in this directory.
