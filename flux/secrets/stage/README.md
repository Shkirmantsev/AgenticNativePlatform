# stage secrets

Commit only encrypted `*.sops.yaml` secrets to this directory.

Do not commit plaintext secrets here. Generate plaintext locally into `.generated/secrets/stage/`, then run `make encrypt-secrets ENV=stage` to produce encrypted files in this directory.
