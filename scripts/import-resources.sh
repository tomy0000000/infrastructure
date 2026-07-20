#!/usr/bin/env bash
set -euo pipefail
#MISE description="Import existing resources into Terraform state"
#MISE dir="staging"

# Load provider credentials. In CI they come from the runner's secrets; when
# running locally, source them from instance/<env>.env (gitignored).
load_env() {
  if [[ -z "${CI:-}" ]]; then
    local env_file="../instance/${MISE_ENV:-staging}.env"
    if [[ ! -f "$env_file" ]]; then
      echo "Env file not found: $env_file" >&2
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
  local existing key name
  existing=$(curl -sf \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/$TF_VAR_cloudflare_account_id/r2/buckets" \
    | jq -r '.result.buckets[]?.name')
  echo "Existing buckets in account:"
  echo "$existing"

  while read -r key name; do
    if echo "$existing" | grep -qx "$name"; then
      terraform import -input=false \
        "module.r2_${key}.cloudflare_r2_bucket.this" \
        "${TF_VAR_cloudflare_account_id}/${name}/default"
    else
      echo "Bucket ${name} does not exist yet, plan will create it"
    fi
  done < <(yq -r '.buckets | to_entries | .[] | .key + " " + .value.name' config.yaml)
}

load_env
import_buckets
