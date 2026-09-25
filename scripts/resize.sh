#!/usr/bin/env bash
set -euo pipefail
#MISE description="Swap an environment's DOKS node pool to the size in config.yaml, keeping the cluster"

ENVS=(staging production)
DEFAULT_TAG="terraform:default-node-pool"
POOL_LABEL="doks.digitalocean.com/node-pool-id"

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

env_file="instance/${env}.env"
if [[ ! -f "$env_file" ]]; then
  echo "$env: env file not found: $env_file" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "$env_file"
set +a
# doctl reads its own variable name, not the one the Terraform provider uses.
export DIGITALOCEAN_ACCESS_TOKEN="$DIGITALOCEAN_TOKEN"

cluster="$(yq -r '.kubernetes.name // ""' "$env/config.yaml")"
size="$(yq -r '.kubernetes.node.size' "$env/config.yaml")"
min="$(yq -r '.kubernetes.node.min' "$env/config.yaml")"
max="$(yq -r '.kubernetes.node.max' "$env/config.yaml")"
if [[ -z "$cluster" ]]; then
  echo "$env: config.yaml defines no kubernetes cluster" >&2
  exit 1
fi

# Draining the wrong environment's nodes is the mistake to rule out first.
context="$(kubectl config current-context 2> /dev/null || true)"
if [[ "$context" != *"$cluster" ]]; then
  echo "kube context $context does not match $env cluster $cluster," \
    "run 'mise run kubeconfig $env' first" >&2
  exit 1
fi

# Must match the pool name in template/doks/main.tf.
name="${cluster}-nodepool"
old_name="${name}-old"

pools() {
  doctl kubernetes cluster node-pool list "$cluster" -o json
}

# Pools are found by name and size rather than by the tag, so a rerun after a
# failure picks up wherever the previous run stopped.
pool_id() {
  pools | name="$1" size="$3" yq -r ".[] | select(.name == strenv(name) and .size $2 strenv(size)) | .id"
}

old_id="$(pool_id "$old_name" != "$size")"
[[ -z "$old_id" ]] && old_id="$(pool_id "$name" != "$size")"
new_id="$(pool_id "$name" == "$size")"

if [[ -z "$old_id" ]]; then
  if [[ -z "$new_id" ]]; then
    echo "$env: no pool named $name or $old_name in $cluster" >&2
    exit 1
  fi
  echo "$env: $name is already $size"
  exit 0
fi

# doctl replaces the whole tag set on update, so every call repeats it.
tags=()
while IFS= read -r tag; do
  tags+=(--tag "$tag")
done < <(pools | id="$old_id" default="$DEFAULT_TAG" \
  yq -r '.[] | select(.id == strenv(id)) | .tags[] | select(. != strenv(default))')

# Frees the name Terraform expects, while the old pool keeps the default tag.
if [[ -z "$new_id" ]]; then
  doctl kubernetes cluster node-pool update "$cluster" "$old_id" \
    --name "$old_name" "${tags[@]}" --tag "$DEFAULT_TAG" > /dev/null
  echo "$env: renamed old pool $old_id to $old_name"

  doctl kubernetes cluster node-pool create "$cluster" \
    --name "$name" --size "$size" --count "$min" \
    --auto-scale --min-nodes "$min" --max-nodes "$max" "${tags[@]}" > /dev/null
  new_id="$(pool_id "$name" == "$size")"
  echo "$env: created pool $new_id at $size"
fi

echo "$env: waiting for nodes in $new_id to register"
until [[ -n "$(kubectl get nodes -l "$POOL_LABEL=$new_id" -o name)" ]]; do
  sleep 10
done
kubectl wait node -l "$POOL_LABEL=$new_id" --for=condition=Ready --timeout=10m

# Cordon every old node before draining any, so evicted pods cannot land on a
# sibling that is next in line. The pool ID label survives the rename, the
# pool name label does not.
kubectl cordon -l "$POOL_LABEL=$old_id"
kubectl drain -l "$POOL_LABEL=$old_id" --ignore-daemonsets --delete-emptydir-data --timeout=10m

# The provider adopts whichever pool carries the tag, so it moves last.
doctl kubernetes cluster node-pool update "$cluster" "$old_id" \
  --name "$old_name" "${tags[@]}" > /dev/null
doctl kubernetes cluster node-pool update "$cluster" "$new_id" \
  --name "$name" "${tags[@]}" --tag "$DEFAULT_TAG" > /dev/null
echo "$env: moved $DEFAULT_TAG to $new_id"

doctl kubernetes cluster node-pool delete "$cluster" "$old_id" --force
echo "$env: deleted old pool $old_id, run 'terraform -chdir=$env plan' and expect no changes"
