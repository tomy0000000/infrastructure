#!/usr/bin/env bash
set -euo pipefail

# Runs as the presync hook of the envoy-gateway release, with its version as
# the only argument, and applies the matching CRDs chart with server-side
# apply. The chart cannot be a Helm release of its own: its release record is
# over the 1 MB Secret limit. --force-conflicts takes the six Gateway API CRDs
# that DOKS pre-installs away from its field manager.

version="${1:?usage: ${0##*/} <envoy-gateway version>}"

context="$(kubectl config current-context 2> /dev/null || true)"
if [[ -z "$context" ]]; then
  echo "no current kube context, run 'mise run kubeconfig <env>' first" >&2
  exit 1
fi
echo "gateway CRDs: applying gateway-crds-helm $version on $context"

helm template gateway-crds oci://docker.io/envoyproxy/gateway-crds-helm \
  --version "$version" \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=experimental \
  --set crds.envoyGateway.enabled=true |
  kubectl apply --server-side --force-conflicts --field-manager=envoy-gateway-crds -f -

# DOKS already leaves a newer bundle-version alone, this states it outright.
kubectl annotate crd \
  gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  grpcroutes.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  referencegrants.gateway.networking.k8s.io \
  tlsroutes.gateway.networking.k8s.io \
  doks.digitalocean.com/install-policy=external --overwrite
