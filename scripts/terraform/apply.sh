#!/usr/bin/env bash
set -euo pipefail
#MISE description="Apply the plan saved by terraform:plan in <env>/tfplan"

ENVS=(staging production)

env="${1:-}"
if [[ -z "$env" ]]; then
  echo "usage: ${0##*/} <${ENVS[*]}>" >&2
  exit 1
fi

matched=""
for candidate in "${ENVS[@]}"; do
  [[ "$candidate" == "$env" ]] && matched="$candidate"
done
if [[ -z "$matched" ]]; then
  echo "unknown environment: $env (expected one of: ${ENVS[*]})" >&2
  exit 1
fi

if [[ ! -f "$env/tfplan" ]]; then
  echo "$env: no saved plan, run 'mise run terraform:plan $env' first" >&2
  exit 1
fi

env_file="instance/${env}.env"
if [[ ! -f "$env_file" ]]; then
  echo "$env: env file not found: $env_file" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "$env_file"
set +a

terraform -chdir="$env" apply -input=false tfplan
