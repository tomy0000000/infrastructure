#!/usr/bin/env bash
set -euo pipefail
#MISE description="Import existing resources into Terraform state"

ENVS=(staging production)

# Load provider credentials. In CI they come from the runner's secrets; when
# running locally, source them from instance/<env>.env (gitignored).
load_env() {
  local env="$1"
  if [[ -z "${CI:-}" ]]; then
    local env_file="instance/${env}.env"
    if [[ ! -f "$env_file" ]]; then
      echo "$env: env file not found: $env_file" >&2
      exit 1
    fi
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi

  : "${CLOUDFLARE_API_TOKEN:?}"
  : "${TF_VAR_cloudflare_account_id:?}"
}

import_buckets() {
  local env="$1"
  local key name out
  while read -r key name; do
    # Capture terraform's output so a clean import stays quiet; show it on failure.
    if out=$(terraform -chdir="$env" import -input=false \
        "module.r2_${key}.cloudflare_r2_bucket.this" \
        "${TF_VAR_cloudflare_account_id}/${name}/default" 2>&1); then
      echo "$env: imported ${name}"
    else
      echo "$env: import of ${name} failed, assuming absent, plan will create it"
      echo "$out" >&2
    fi
  done < <(yq -r '.buckets | to_entries | .[] | .key + " " + .value.name' "$env/config.yaml")
}

for env in "${ENVS[@]}"; do
  if [[ ! -f "$env/config.yaml" ]]; then
    echo "$env: no config.yaml, skipping"
    continue
  fi
  load_env "$env"
  import_buckets "$env"
done
