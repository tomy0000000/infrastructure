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
  : "${DIGITALOCEAN_TOKEN:?}"
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


# cloudflare_r2_custom_domain does not support import,
# so we have to inject it into the state manually.
import_bucket_hosts() {
  local env="$1"
  local key bucket host address resp attrs
  while read -r key bucket host; do
    [[ -z "$host" ]] && continue # bucket without bucket_hosts
    address="module.r2_${key}.cloudflare_r2_custom_domain.this[\"${host}\"]"
    if [[ -n $(terraform -chdir="$env" state list "$address" 2>/dev/null) ]]; then
      echo "$env: bucket host ${host} already in state"
      continue
    fi
    resp=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/${TF_VAR_cloudflare_account_id}/r2/buckets/${bucket}/domains/custom/${host}")
    if [[ $(jq -r '.success' <<<"$resp") != "true" ]]; then
      echo "$env: bucket host ${host} not found, plan will create it"
      continue
    fi
    attrs=$(jq --arg aid "$TF_VAR_cloudflare_account_id" --arg bucket "$bucket" '{
      account_id: $aid,
      bucket_name: $bucket,
      domain: .result.domain,
      enabled: .result.enabled,
      zone_id: .result.zoneId,
      zone_name: .result.zoneName,
      min_tls: (.result.minTLS // null),
      ciphers: null,
      jurisdiction: "default",
      status: {ownership: .result.status.ownership, ssl: .result.status.ssl}
    }' <<<"$resp")
    if terraform -chdir="$env" state pull \
      | jq --arg mod "module.r2_${key}" --arg host "$host" --argjson attrs "$attrs" '
          {index_key: $host, schema_version: 0, attributes: $attrs, sensitive_attributes: []} as $inst
          | def match: .module == $mod and .type == "cloudflare_r2_custom_domain" and .name == "this";
            if any(.resources[]; match)
            then .resources |= map(if match then .instances += [$inst] else . end)
            else .resources += [{
              module: $mod, mode: "managed", type: "cloudflare_r2_custom_domain", name: "this",
              provider: "provider[\"registry.terraform.io/cloudflare/cloudflare\"]",
              instances: [$inst]
            }]
            end
          | .serial += 1
        ' \
      | terraform -chdir="$env" state push - > /dev/null 2>&1; then
      echo "$env: adopted bucket host ${host} into state"
    else
      echo "$env: state injection for bucket host ${host} failed" >&2
      exit 1
    fi
  done < <(yq -r '.buckets | to_entries | .[] | .key + " " + .value.name + " " + ((.value.bucket_hosts // [])[])' "$env/config.yaml")
}

# A cluster must never be double-created, so a lookup that succeeds but fails
# to import is fatal rather than falling through to create.
import_cluster() {
  local env="$1"
  local name resp cluster_id
  name=$(yq -r '.kubernetes.name // ""' "$env/config.yaml")
  [[ -z "$name" ]] && return 0

  if [[ -n $(terraform -chdir="$env" state list "module.doks.digitalocean_kubernetes_cluster.this" 2>/dev/null) ]]; then
    echo "$env: cluster ${name} already in state"
    return 0
  fi

  # The API has no name filter for clusters, so match client side.
  resp=$(curl -s -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
    "https://api.digitalocean.com/v2/kubernetes/clusters?per_page=200")
  if [[ $(jq -r 'has("kubernetes_clusters")' <<<"$resp") != "true" ]]; then
    echo "$env: cluster lookup for ${name} failed: $(jq -c '.message // .' <<<"$resp")" >&2
    exit 1
  fi
  cluster_id=$(jq -r --arg name "$name" \
    'first(.kubernetes_clusters[] | select(.name == $name) | .id) // empty' <<<"$resp")
  if [[ -z "$cluster_id" ]]; then
    echo "$env: cluster ${name} not found, plan will create it"
    return 0
  fi

  # The default node pool rides along, because the provider tags a lone pool
  # as terraform:default-node-pool during import.
  if terraform -chdir="$env" import -input=false \
      "module.doks.digitalocean_kubernetes_cluster.this" "$cluster_id" > /dev/null 2>&1; then
    echo "$env: imported cluster ${name}"
  else
    echo "$env: import of cluster ${name} failed" >&2
    exit 1
  fi
}

for env in "${ENVS[@]}"; do
  if [[ ! -f "$env/config.yaml" ]]; then
    echo "$env: no config.yaml, skipping"
    continue
  fi
  if [[ ! -d "$env/.terraform" ]]; then
    echo "$env: not initialised, skipping"
    continue
  fi
  load_env "$env"
  import_zones "$env"
  import_buckets "$env"
  import_bucket_hosts "$env"
  import_cluster "$env"

  # These resources does not support import, but its create is idempotent
  # - cloudflare_r2_bucket_cors
  # - cloudflare_r2_bucket_lifecycle
  # - cloudflare_r2_managed_domain
done
