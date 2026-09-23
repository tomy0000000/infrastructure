# Cluster

Everything that runs on the DOKS cluster, as helmfile releases. Terraform owns
the cluster, helmfile owns what is inside it.

## Layout

- `platform/` shared services every app depends on. Today: Envoy Gateway,
  cert-manager, origin-ca-issuer, External Secrets Operator, and
  `charts/cluster-config`, a local chart for cluster-scoped objects no upstream
  chart ships. Today: the `eg` GatewayClass that binds Gateways to Envoy Gateway,
  and the one `shared` Gateway every app attaches routes to, since each Gateway
  costs a DigitalOcean load balancer.

## Environments

Environments read `../staging/config.yaml` and `../production/config.yaml`, so
each environment keeps the one config file Terraform already uses. The Gateway
listener hostname derives from the zone defined there.

## CRDs

Envoy Gateway needs Gateway API v1.6.1 experimental, for TCPRoute and UDPRoute.
Its CRDs ship in `gateway-crds-helm`, but that chart cannot be a Helm release:
the release record Helm writes to a Secret is over the 1 MB limit, and every
release carries the whole chart source, so no split of it fits either.

So the `envoy-gateway` release carries a `presync` hook,
`cluster/scripts/apply-gateway-crds.sh`, that renders `gateway-crds-helm` at the
release's own version and server-side applies it. One version pin moves the
controller and its CRDs together, and `helm diff` still covers the controller.
`presync` only fires when the release syncs, so `mise run charts <env> sync -l
name=envoy-gateway` is the way to force the CRDs alone.

origin-ca-issuer has the same shape on a smaller scale. Its chart ships no CRDs
at all: `OriginIssuer` and `ClusterOriginIssuer` live in the project repo at the
tag matching the chart's `appVersion`. A `presync` hook,
`cluster/scripts/apply-origin-ca-crds.sh`, reads that `appVersion` from the
chart and server-side applies both files from that tag, so the chart version
stays the only pin.

### DOKS pre-installs six of them

Every DOKS cluster arrives with six Gateway API CRDs (GatewayClass, Gateway,
HTTPRoute, GRPCRoute, TLSRoute, ReferenceGrant) at v1.2.1, and holds their
fields as a server-side apply manager. `--force-conflicts` takes them over.
DOKS then leaves them alone because their `bundle-version` is newer than its
own, and the hook also sets `doks.digitalocean.com/install-policy: external` so
that holds even if DOKS one day ships a newer bundle than ours.

Never delete those six expecting DOKS to put them back. It installs them at
provisioning and never reconciles them afterwards, so the only way to a
DOKS-shaped cluster again is to recreate the cluster.

## Secrets

Every workload Secret is fetched from 1Password by External Secrets Operator
through its `onepasswordSDK` provider, which talks to the 1Password API with a
Service Account token. No Connect server. The `onepassword` ClusterSecretStore
in `cluster-config` is scoped to the `Develop` vault, and a new secret is an
`ExternalSecret` next to the release that consumes it.

Exactly one secret reaches the cluster by another path: that Service Account
token. It lives in `instance/<env>.env` as `ONE_PASSWORD_ESO_SERVICE_ACCOUNT_TOKEN`, next
to the provider tokens, and `mise run charts` loads that file the way
`import-resources.sh` does. `platform/values/external-secrets.yaml.gotmpl`
hands it to the chart as an extra object. `instance/README.md` has the setup.

The account is on the Family plan: 1,000 reads per hour per token and 1,000
reads per day across the account. So `refreshInterval` on an ExternalSecret is
`1h`, never the `1m` in upstream examples, which alone would burn the daily
budget on one secret.

## Restore

Copy-paste, top to bottom. Swap `production` for `staging` for the other
environment. Skip a block if what it produces still exists.

Tooling, on a fresh machine:

```
mise install && helm plugin install https://github.com/databus23/helm-diff --verify=false
```

Cluster, if it is gone. The plan creates it from `production/config.yaml`:

```
gh workflow run apply-production.yml && mise run kubeconfig production
```

Everything else. `instance/<env>.env` has to exist, see `instance/README.md`.
`needs:` orders the releases and the presync hooks apply CRDs on the way in,
so a fresh cluster and an old one take the same command:

```
mise run charts production apply
```

Done when every pod is Running:

```
kubectl get pods -A
```
