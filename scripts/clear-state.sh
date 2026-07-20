#!/usr/bin/env bash
set -euo pipefail
#MISE description="Clear local Terraform state files"

ENVS=(staging production)
STATE_FILES=(terraform.tfstate terraform.tfstate.backup)

for env in "${ENVS[@]}"; do
  present=()
  for f in "${STATE_FILES[@]}"; do
    [[ -f "$env/$f" ]] && present+=("$env/$f")
  done

  if [[ "${#present[@]}" -eq 0 ]]; then
    echo "$env: no local state files to clear"
    continue
  fi

  rm -f "${present[@]}"
  echo "$env: removed ${present[*]}"
done
