#!/usr/bin/env bash
set -euo pipefail

required=(docker kubectl helm kind kustomize flux)
missing=()

for cmd in "${required[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[ok] %s\n' "$cmd"
  else
    printf '[missing] %s\n' "$cmd"
    missing+=("$cmd")
  fi
done

if ((${#missing[@]} > 0)); then
  echo
  echo "Missing required tools: ${missing[*]}"
  exit 1
fi

echo
echo "All required tools are installed."
