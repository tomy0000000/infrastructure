#!/usr/bin/env bash
set -euo pipefail
#MISE description="Clear local Terraform state files"
#MISE dir="staging"

# Local state Terraform writes into the working directory. Clearing these lets
# you re-import from remote via the import-resources task.
state_files=(terraform.tfstate terraform.tfstate.backup)

present=()
for f in "${state_files[@]}"; do
  [[ -f "$f" ]] && present+=("$f")
done

if [[ "${#present[@]}" -eq 0 ]]; then
  echo "No local state files to clear"
  exit 0
fi

rm -f "${present[@]}"
echo "Removed: ${present[*]}"
