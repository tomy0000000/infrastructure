#!/usr/bin/env bash
set -euo pipefail

# Runs as the presync hook of the kube-prometheus-stack release, with its
# version as the only argument, and applies the Prometheus Operator CRDs that
# chart ships with server-side apply. Helm installs CRDs once and never
# upgrades them, so the chart's own copy is disabled in favor of this.

version="${1:?usage: ${0##*/} <kube-prometheus-stack version>}"

context="$(kubectl config current-context 2> /dev/null || true)"
if [[ -z "$context" ]]; then
  echo "no current kube context, run 'mise run kubeconfig <env>' first" >&2
  exit 1
fi
echo "prometheus CRDs: applying kube-prometheus-stack $version CRDs on $context"

helm show crds kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --version "$version" |
  kubectl apply --server-side --force-conflicts --field-manager=prometheus-crds -f -
