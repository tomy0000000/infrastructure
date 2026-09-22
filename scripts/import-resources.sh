#!/usr/bin/env bash
set -euo pipefail
#MISE description="Import existing resources into Terraform state"

# Environment -> import steps to skip (staging has no cluster or instances)
declare -A ENVS=(
  [staging]="cluster instances instance_dns instance_network"
  [production]=""
)

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
  : "${LINODE_TOKEN:?}"
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

# cloudflare_r2_bucket_cors and cloudflare_r2_bucket_lifecycle do not support
# import either, but their read does refresh, so a stub carrying only the
# identity attributes is enough and the next plan fills the rules back in.
import_bucket_rules() {
  local env="$1"
  local key name hosts kind index_key address
  while read -r key name hosts; do
    # Refreshing rules against a bucket that is not in state yet would 404.
    if [[ -z $(terraform -chdir="$env" state list "module.r2_${key}.cloudflare_r2_bucket.this" 2>/dev/null) ]]; then
      echo "$env: ${name} not in state, plan will create its rules"
      continue
    fi
    for kind in cors lifecycle; do
      index_key=null
      if [[ "$kind" == "cors" ]]; then
        [[ "$hosts" -eq 0 ]] && continue # count = 0, no instance to adopt
        index_key=0
      fi
      address="module.r2_${key}.cloudflare_r2_bucket_${kind}.this"
      [[ "$index_key" == "0" ]] && address="${address}[0]"
      if [[ -n $(terraform -chdir="$env" state list "$address" 2>/dev/null) ]]; then
        echo "$env: ${name} ${kind} already in state"
        continue
      fi
      if terraform -chdir="$env" state pull \
        | jq --arg mod "module.r2_${key}" --arg type "cloudflare_r2_bucket_${kind}" \
             --arg aid "$TF_VAR_cloudflare_account_id" --arg bucket "$name" \
             --argjson index_key "$index_key" '
            # 500 is the schema version the Cloudflare provider writes for these.
            ({schema_version: 500, sensitive_attributes: [], attributes: {
                account_id: $aid, bucket_name: $bucket, jurisdiction: "default", rules: null}}
              + (if $index_key == null then {} else {index_key: $index_key} end)) as $inst
            | def match: .module == $mod and .type == $type and .name == "this";
              if any(.resources[]; match)
              then .resources |= map(if match then .instances += [$inst] else . end)
              else .resources += [{
                module: $mod, mode: "managed", type: $type, name: "this",
                provider: "provider[\"registry.terraform.io/cloudflare/cloudflare\"]",
                instances: [$inst]
              }]
              end
            | .serial += 1
          ' \
        | terraform -chdir="$env" state push - > /dev/null 2>&1; then
        echo "$env: adopted ${name} ${kind} into state"
      else
        echo "$env: state injection for ${name} ${kind} failed" >&2
        exit 1
      fi
    done
  done < <(yq -r '.buckets | to_entries | .[] | .key + " " + .value.name + " " + ((.value.access_hosts // []) | length | tostring)' "$env/config.yaml")
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

# A compute instance must never be double-created, so a lookup that succeeds
# but fails to import is fatal rather than falling through to create.
import_instances() {
  local env="$1"
  local key name resp instance_id
  while read -r key name; do
    if [[ -n $(terraform -chdir="$env" state list "module.linode_${key}.linode_instance.this" 2>/dev/null) ]]; then
      echo "$env: instance ${name} already in state"
      continue
    fi
    resp=$(curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
      -H "X-Filter: {\"label\": \"${name}\"}" \
      "https://api.linode.com/v4/linode/instances")
    if [[ $(jq -r 'has("data")' <<<"$resp") != "true" ]]; then
      echo "$env: instance lookup for ${name} failed: $(jq -c '.errors' <<<"$resp")" >&2
      exit 1
    fi
    instance_id=$(jq -r '.data[0].id // empty' <<<"$resp")
    if [[ -z "$instance_id" ]]; then
      echo "$env: instance ${name} not found, plan will create it"
      continue
    fi
    if terraform -chdir="$env" import -input=false \
        "module.linode_${key}.linode_instance.this" "$instance_id" > /dev/null 2>&1; then
      echo "$env: imported instance ${name}"
    else
      echo "$env: import of instance ${name} failed" >&2
      exit 1
    fi
  done < <(yq -r '.instances // {} | to_entries | .[] | .key + " " + .value.name' "$env/config.yaml")
}

# cloudflare_dns_record is imported as <zone_id>/<record_id>, so the records can
# only be adopted once the zone that holds them is itself in state.
import_instance_dns() {
  local env="$1"
  local zone_id key hostname record rname rtype address resp matches record_id
  if [[ -z $(terraform -chdir="$env" state list "module.zone_main.cloudflare_zone.this" 2>/dev/null) ]]; then
    echo "$env: main zone not in state, plan will create the instance records"
    return 0
  fi
  zone_id=$(terraform -chdir="$env" state pull | jq -r 'first(.resources[]
    | select(.module == "module.zone_main" and .type == "cloudflare_zone")
    | .instances[0].attributes.id)')
  while read -r key hostname; do
    for record in a:A aaaa:AAAA; do
      rname=${record%%:*}
      rtype=${record##*:}
      address="module.linode_${key}.cloudflare_dns_record.${rname}"
      if [[ -n $(terraform -chdir="$env" state list "$address" 2>/dev/null) ]]; then
        echo "$env: ${rtype} record ${hostname} already in state"
        continue
      fi
      resp=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name.exact=${hostname}&type=${rtype}")
      if [[ $(jq -r '.success' <<<"$resp") != "true" ]]; then
        echo "$env: ${rtype} record lookup for ${hostname} failed: $(jq -c '.errors' <<<"$resp")" >&2
        exit 1
      fi
      # A name and type can hold several records, and guessing adopts the wrong one.
      matches=$(jq -r '.result | length' <<<"$resp")
      if [[ "$matches" -gt 1 ]]; then
        echo "$env: ${rtype} record ${hostname} has ${matches} matches, import it by hand" >&2
        exit 1
      fi
      record_id=$(jq -r '.result[0].id // empty' <<<"$resp")
      if [[ -z "$record_id" ]]; then
        echo "$env: ${rtype} record ${hostname} not found, plan will create it"
        continue
      fi
      if terraform -chdir="$env" import -input=false \
          "$address" "${zone_id}/${record_id}" > /dev/null 2>&1; then
        echo "$env: imported ${rtype} record ${hostname}"
      else
        echo "$env: import of ${rtype} record ${hostname} failed"
      fi
    done
  done < <(yq -r '.instances // {} | to_entries | .[] | .key + " " + .value.hostname' "$env/config.yaml")
}

# Skips when already in state or when there is nothing to adopt, and fails hard
# otherwise, since a stray create here allocates a fresh IPv6 range.
import_or_die() {
  local env="$1" address="$2" id="$3" desc="$4"
  if [[ -n $(terraform -chdir="$env" state list "$address" 2>/dev/null) ]]; then
    echo "$env: ${desc} already in state"
  elif [[ -z "$id" ]]; then
    echo "$env: ${desc} not found, plan will create it"
  elif terraform -chdir="$env" import -input=false "$address" "$id" > /dev/null 2>&1; then
    echo "$env: imported ${desc}"
  else
    echo "$env: import of ${desc} failed" >&2
    exit 1
  fi
}

# linode_ipv6_range imports by its range and linode_rdns by address, both of
# which only the instance's own IP listing reveals, so this runs after it.
import_instance_network() {
  local env="$1"
  local key name mod instance_id resp v4 range route_target
  while read -r key name; do
    mod="module.linode_${key}"
    instance_id=$(terraform -chdir="$env" state pull | jq -r --arg mod "$mod" 'first(.resources[]
      | select(.module == $mod and .type == "linode_instance")
      | .instances[0].attributes.id) // empty')
    if [[ -z "$instance_id" ]]; then
      echo "$env: instance ${name} not in state, plan will create its network"
      continue
    fi
    resp=$(curl -s -H "Authorization: Bearer $LINODE_TOKEN" \
      "https://api.linode.com/v4/linode/instances/${instance_id}/ips")
    if [[ $(jq -r 'has("ipv4")' <<<"$resp") != "true" ]]; then
      echo "$env: ip lookup for ${name} failed: $(jq -c '.errors' <<<"$resp")" >&2
      exit 1
    fi
    v4=$(jq -r 'first(.ipv4.public[].address) // empty' <<<"$resp")
    range=$(jq -r 'first(.ipv6.global[].range) // empty' <<<"$resp")
    import_or_die "$env" "${mod}.linode_ipv6_range.this" "$range" "${name} ipv6 range"
    import_or_die "$env" "${mod}.linode_rdns.v4" "$v4" "${name} v4 rdns"
    # main.tf puts the AAAA and the v6 PTR on the first address of the range.
    import_or_die "$env" "${mod}.linode_rdns.v6" "${range:+${range}1}" "${name} v6 rdns"
    # Read never back-fills these, and null plans as a replacement (range) or an update (rdns).
    route_target=$(jq -r 'first(.ipv6.global[].route_target) // empty' <<<"$resp")
    if terraform -chdir="$env" state pull \
      | jq --arg mod "$mod" --argjson lid "$instance_id" --arg rt "$route_target" '
          .resources |= map(
            if .module == $mod and .type == "linode_ipv6_range"
            then .instances |= map(.attributes += {linode_id: $lid, route_target: $rt})
            elif .module == $mod and .type == "linode_rdns"
            then .instances |= map(.attributes += {wait_for_available: true})
            else . end)
          | .serial += 1' \
      | terraform -chdir="$env" state push - > /dev/null 2>&1; then
      echo "$env: patched ${name} network attributes into state"
    else
      echo "$env: state injection for ${name} network failed" >&2
      exit 1
    fi
  done < <(yq -r '.instances // {} | to_entries | .[] | .key + " " + .value.name' "$env/config.yaml")
}

step() {
  local env="$1" name="$2"
  if [[ " ${ENVS[$env]} " == *" $name "* ]]; then
    echo "$env: skipping $name"
    return
  fi
  "import_$name" "$env"
}

for env in "${!ENVS[@]}"; do
  if [[ ! -f "$env/config.yaml" ]]; then
    echo "$env: no config.yaml, skipping"
    continue
  fi
  if [[ ! -d "$env/.terraform" ]]; then
    echo "$env: not initialised, skipping"
    continue
  fi
  load_env "$env"
  step "$env" zones
  step "$env" buckets
  step "$env" bucket_hosts
  step "$env" bucket_rules
  step "$env" cluster
  step "$env" instances
  step "$env" instance_dns
  step "$env" instance_network

  # These resources does not support import, but its create is idempotent
  # - cloudflare_r2_managed_domain
done
