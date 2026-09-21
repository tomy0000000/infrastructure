#!/usr/bin/env bash
set -euo pipefail
#MISE description="Add an environment's DOKS cluster to your kubeconfig as a context"

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

if [[ ! -d "$env/.terraform" ]]; then
  echo "$env: not initialised, run terraform -chdir=$env init first" >&2
  exit 1
fi

if ! command -v doctl > /dev/null 2>&1; then
  echo "doctl not found, run mise install" >&2
  exit 1
fi

# The 1Password shell plugin is only a shell function, so it never reaches a
# script or a kubectl subprocess. Where it is configured, call the wrapper it
# stands for, since doctl then holds no credential of its own.
plugins_sh="$HOME/.config/op/plugins.sh"
if command -v op > /dev/null 2>&1 &&
  [[ -f "$plugins_sh" && "$(<"$plugins_sh")" == *"doctl()"* ]]; then
  doctl_cmd=(op plugin run -- doctl)
else
  doctl_cmd=(doctl)
fi

# terraform still exits 0 and prints nothing for an output that is absent from
# state, so emptiness is the only reliable check.
cluster_id="$(terraform -chdir="$env" output -raw cluster_id 2>/dev/null || true)"
if [[ -z "$cluster_id" ]]; then
  echo "$env: no cluster_id output, run 'terraform -chdir=$env apply' to create" \
    "the cluster or to publish outputs added since the last apply" >&2
  exit 1
fi

if ! "${doctl_cmd[@]}" kubernetes cluster kubeconfig save "$cluster_id"; then
  echo "$env: doctl could not save the kubeconfig, is it authenticated?" >&2
  exit 1
fi

# doctl merges into the first file KUBECONFIG names, falling back to the default.
kubeconfig="${KUBECONFIG:-}"
kubeconfig="${kubeconfig%%:*}"
kubeconfig="${kubeconfig:-$HOME/.kube/config}"

context="$(yq -r '.["current-context"]' "$kubeconfig")"
user="$(context="$context" yq -r '.contexts[] | select(.name == strenv(context)) | .context.user' "$kubeconfig")"

# doctl writes its own argv[0] as the exec command, which carries no credential
# and under the wrapper is an unstable shim path. kubectl execs this directly,
# so it needs the same wrapper. Skip when already rewritten, or the prefix would
# stack on a rerun.
if [[ "${doctl_cmd[0]}" == "op" ]] &&
  [[ "$(user="$user" yq -r '.users[] | select(.name == strenv(user)) | .user.exec.command' "$kubeconfig")" != "op" ]]; then
  user="$user" yq -i '(.users[] | select(.name == strenv(user)) | .user.exec.args) |= (["plugin","run","--","doctl"] + .)' "$kubeconfig"
  user="$user" yq -i '(.users[] | select(.name == strenv(user)) | .user.exec.command) = "op"' "$kubeconfig"
  echo "$env: routed $user through 1Password"
fi

echo "$env: context $context is current in $kubeconfig"
