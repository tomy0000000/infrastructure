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

## `<cluster>-cloudflare-external_dns`

Cloudflare API token external-dns uses to publish records for every
HTTPRoute. Becomes `cloudflare-api-key` in the `external-dns` namespace.

1. Same path as above: **Create Token** → **Create Custom Token**
2. Name it (e.g. `External DNS Production`) and add the permission:
   - **Zone** → **DNS** → **Edit**
3. Under **Zone Resources**, include the zone the records go into
4. **Continue to summary** → **Create Token**, then copy it
5. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-cloudflare-external_dns`, paste the token into **credential**

Two tokens rather than one with both permissions, so revoking either leaves
the other component running.

## `<cluster>-grafana-admin`

Grafana's admin login at `metrics.<zone>`. Becomes `grafana-admin` in the
`monitoring` namespace.

1. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-grafana-admin`
2. Set **username** to the admin login name (e.g. `admin`)
3. Generate a password into **credential**

Grafana reads both only when its database is empty, and its database lives in
the pod without a volume, so a changed password takes effect on the next pod
restart: `kubectl -n monitoring rollout restart deployment
kube-prometheus-stack-grafana`.

An existing Cloudflare token can be edited in place to add a permission or a
zone, so widening access does not mean a new item.

## `<cluster>-email_mcp-token`

Shared token the Caddy sidecar in front of mcp-email-server checks on every
request to `mcp-mail.<zone>`. Becomes `email-mcp-token` in the `email-mcp`
namespace.

1. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-email_mcp-token`
2. Generate a password into **credential**. Letters and digits only, 32 or
   more characters: it is also a URL path segment
   (`https://mcp-mail.<zone>/<token>/mcp`), the form claude.ai connects with

The proxy reads it into an environment variable at start, so a rotated token
takes effect only after `kubectl -n email-mcp rollout restart deployment
email-mcp`. It invalidates every client at once: update the claude.ai
connector and `claude mcp add --header` registrations with the new value.

## `<cluster>-mailcow-email_mcp`

The mailbox mcp-email-server logs into over IMAP. Becomes `email-mcp-imap` in
the `email-mcp` namespace, with the mailbox address as `username` and the app
password as `password`.

1. In the mailcow web UI at `instances.mailcow.hostname`, log in as the
   mailbox → **App passwords** → **Create app password**
2. Name it (e.g. `email-mcp production`)
3. Tick **IMAP** only. Leave SMTP, POP3, EAS, DAV and Sieve unticked: the
   server then cannot send mail or touch Sieve rules no matter what it is
   asked
4. Create it here, in the web UI. App passwords made through the mailcow API
   have been reported to land without their protocols and fail IMAP login
   until re-saved in the UI
5. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-mailcow-email_mcp`
6. Set **username** to the mailbox address (e.g. `tomy@<zone>`), and paste
   the app password into **credential**

The server reads both keys into environment variables at start, so a rotated
password takes effect only after `kubectl -n email-mcp rollout restart
deployment email-mcp`.
