#!/usr/bin/env bash
set -euo pipefail
#MISE description="Run helmfile against an environment's cluster (default: diff)"

ENVS=(staging production)

env="${1:-}"
if [[ -z "$env" ]]; then
  echo "usage: ${0##*/} <${ENVS[*]}> [helmfile args...]" >&2
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

cluster="$(yq -r '.kubernetes.name // ""' "$env/config.yaml")"
if [[ -z "$cluster" ]]; then
  echo "$env: config.yaml defines no kubernetes cluster" >&2
  exit 1
fi

# Applying an environment's charts to another environment's cluster is the one
# mistake this wrapper exists to prevent.
context="$(kubectl config current-context 2> /dev/null || true)"
if [[ "$context" != *"$cluster" ]]; then
  echo "kube context $context does not match $env cluster $cluster," \
    "run 'mise run kubeconfig $env' first" >&2
  exit 1
fi

helmfile --file cluster/helmfile.yaml --environment "$env" "${@:-diff}"
