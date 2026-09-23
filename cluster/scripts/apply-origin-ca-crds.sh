#!/usr/bin/env bash
set -euo pipefail

# Runs as the presync hook of the origin-ca-issuer release, with its chart
# version as the only argument. The chart ships no CRDs: they live in the
# project repo at the tag matching the chart's appVersion, so that tag is
# derived here and the chart version stays the one pin.

chart="oci://ghcr.io/cloudflare/origin-ca-issuer-charts/origin-ca-issuer"
version="${1:?usage: ${0##*/} <origin-ca-issuer chart version>}"

context="$(kubectl config current-context 2> /dev/null || true)"
if [[ -z "$context" ]]; then
  echo "no current kube context, run 'mise run kubeconfig <env>' first" >&2
  exit 1
fi

app="$(helm show chart "$chart" --version "$version" | yq -r .appVersion)"
if [[ -z "$app" || "$app" == "null" ]]; then
  echo "could not read appVersion from chart $version" >&2
  exit 1
fi
echo "origin CA CRDs: applying v$app on $context"

base="https://raw.githubusercontent.com/cloudflare/origin-ca-issuer/v${app}/deploy/crds"
for crd in originissuers clusteroriginissuers; do
  curl -fsSL "$base/cert-manager.k8s.cloudflare.com_${crd}.yaml"
done | kubectl apply --server-side --field-manager=origin-ca-issuer-crds -f -
