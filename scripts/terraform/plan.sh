#!/usr/bin/env bash
set -euo pipefail
#MISE description="Plan an environment the way CI does, saving the plan to <env>/tfplan"

ENVS=(staging production)

env="${1:-}"
if [[ -z "$env" ]]; then
  echo "usage: ${0##*/} <${ENVS[*]}> [terraform plan args...]" >&2
  exit 1
fi
shift

matched=""
for candidate in "${ENVS[@]}"; do
  [[ "$candidate" == "$env" ]] && matched="$candidate"
done
if [[ -z "$matched" ]]; then
  echo "unknown environment: $env (expected one of: ${ENVS[*]})" >&2
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

# State is throwaway, as in CI, so existing resources are imported before every plan.
terraform -chdir="$env" init -input=false > /dev/null
./scripts/import-resources.sh
terraform -chdir="$env" plan -input=false -out=tfplan "$@"
