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

import_zones() {
  local env="$1"
  local key domain resp zone_id
  while read -r key domain; do
    if [[ -n $(terraform -chdir="$env" state list "module.zone_${key}.cloudflare_zone.this" 2>/dev/null) ]]; then
      echo "$env: zone ${domain} already in state"
      continue
    fi
    # Imports need the zone ID; resolve it from the domain via the API.
    resp=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/zones?name=${domain}&account.id=${TF_VAR_cloudflare_account_id}")
    if [[ $(jq -r '.success' <<<"$resp") != "true" ]]; then
      echo "$env: zone lookup for ${domain} failed: $(jq -c '.errors' <<<"$resp")" >&2
      exit 1
    fi
    zone_id=$(jq -r '.result[0].id // empty' <<<"$resp")
    if [[ -z "$zone_id" ]]; then
      echo "$env: zone ${domain} not found, plan will create it"
      continue
    fi
    if terraform -chdir="$env" import -input=false \
        "module.zone_${key}.cloudflare_zone.this" "$zone_id" > /dev/null 2>&1; then
      echo "$env: imported zone ${domain}"
    else
      echo "$env: import of zone ${domain} failed"
    fi
  done < <(yq -r '.zones // {} | to_entries | .[] | .key + " " + .value' "$env/config.yaml")
}

import_buckets() {
  local env="$1"
  local key name
  while read -r key name; do
    if [[ -n $(terraform -chdir="$env" state list "module.r2_${key}.cloudflare_r2_bucket.this" 2>/dev/null) ]]; then
      echo "$env: ${name} already in state"
      continue
    fi
    if terraform -chdir="$env" import -input=false \
        "module.r2_${key}.cloudflare_r2_bucket.this" \
        "${TF_VAR_cloudflare_account_id}/${name}/default" > /dev/null 2>&1; then
      echo "$env: imported ${name}"
    else
      echo "$env: import of ${name} failed, assuming absent, plan will create it"
    fi
  done < <(yq -r '.buckets | to_entries | .[] | .key + " " + .value.name' "$env/config.yaml")
}

for env in "${ENVS[@]}"; do
  if [[ ! -f "$env/config.yaml" ]]; then
    echo "$env: no config.yaml, skipping"
    continue
  fi
  load_env "$env"
  import_zones "$env"
  import_buckets "$env"
done
