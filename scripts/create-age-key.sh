#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="${ROOT_DIR}/.sops"
KEY_FILE="${KEY_DIR}/age.agekey"
PUB_FILE="${KEY_DIR}/age.pub"
mkdir -p "${KEY_DIR}"
if [[ ! -f "${KEY_FILE}" ]]; then
  age-keygen -o "${KEY_FILE}"
fi
grep '^# public key:' "${KEY_FILE}" | awk '{print $4}' > "${PUB_FILE}"
RECIPIENT="$(cat "${PUB_FILE}")"
cat > "${ROOT_DIR}/.sops.yaml" <<EOF
creation_rules:
  - path_regex: secrets/.*\.ya?ml
    age: ${RECIPIENT}
EOF
echo "Created ${KEY_FILE} and updated .sops.yaml with recipient ${RECIPIENT}"
