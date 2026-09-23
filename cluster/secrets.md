# Cluster Secrets

Instructions for creating the credentials the cluster fetches from 1Password.

Every one of them is an item in the `Develop` vault. External Secrets Operator
reads it through the `onepassword` ClusterSecretStore and writes a Kubernetes
Secret next to the release that consumes it, declared as an `ExternalSecret`
in `cluster/`. Nothing here is committed or typed into the cluster by hand.

Items are named `<cluster>-<vendor>-<purpose>`: dashes separate the three
parts, underscores stand in for spaces inside one, so `endurance-cloudflare-origin_ca`
reads as cluster `endurance`, vendor `cloudflare`, purpose `origin ca`. Each
cluster gets its own items, so staging and production never share a token.
Items use the **API Credential** type, so the token sits in the `credential`
field and an `ExternalSecret` addresses it as `<item>/credential`. Verify with
`kubectl get externalsecret -A`: every row `READY True`.

Rotation is editing the item. ESO picks the new value up within the hour, or
right away with
`kubectl -n <namespace> annotate externalsecret <name> force-sync=$(date +%s)`.

## `<cluster>-cloudflare-origin_ca`

Cloudflare API token origin-ca-issuer uses to request Origin CA certificates.
Becomes `cloudflare-api-key` in the `origin-ca-issuer` namespace.

1. Go to [Cloudflare dashboard](https://dash.cloudflare.com) → profile icon
   (top right) → **Profile** → **API Tokens**
2. Click **Create Token** → **Create Custom Token**
3. Name it (e.g. `<Cluster Name> Production`) and add the permission:
   - **Zone** → **SSL and Certificates** → **Edit**
4. Under **Zone Resources**, include the specific zone the certificates are
   for
5. **Continue to summary** → **Create Token**, then copy it
6. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-cloudflare-origin_ca`, paste the token into **credential**

Origin CA Service Keys are the older way to do this and were deprecated by
Cloudflare on 2026-03-19. Only API tokens work with the issuer now.
