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

## `<cluster>-cloudflare-postgres_backup`

R2 S3 key the barman-cloud plugin writes base backups and WAL with. Becomes
`r2-backup` in the `postgres` namespace, with the Access Key ID as
`accessKeyId` and the Secret Access Key as `secretAccessKey`.

1. Go to [Cloudflare dashboard](https://dash.cloudflare.com) → **R2** →
   **Manage API tokens** → **Create Account API token**
2. Name it (e.g. `<Cluster Name> Postgres Backup`), pick **Object Read &
   Write**, and under **Specify bucket(s)** apply it to `buckets.postgres.name`
   only
3. **Create API Token**, then copy the **Access Key ID** and **Secret Access
   Key**. Cloudflare shows the secret only once
4. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-cloudflare-postgres_backup`
5. Set **username** to the Access Key ID, and paste the Secret Access Key
   into **credential**

## `<cluster>-postgres-<app>`

Password of the role `<app>` that owns the database `<app>` in the shared
Postgres. Becomes `main-<app>` in the `postgres` namespace, in the
`kubernetes.io/basic-auth` shape CNPG reads, and whatever the app's own
`ExternalSecret` makes of it in the app's namespace.

1. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-postgres-<app>`
2. Set **username** to `<app>`, the role name
3. Generate a password into **credential**. Letters and digits only: it is
   embedded in a `postgres://` URL unescaped

CNPG applies a changed password to the role within the hour, when ESO refreshes
the Secret. The app only reads its URL at start, so follow a rotation with a
restart of the app's Deployment.

## `<cluster>-cloudflare-clickhouse_backup`

R2 S3 key ClickHouse writes its backups with. Becomes `r2-backup` in the
`plausible` namespace, with the Access Key ID as `accessKeyId` and the Secret
Access Key as `secretAccessKey`.

Same steps as `<cluster>-cloudflare-postgres_backup`, with the token named
`<Cluster Name> ClickHouse Backup`, applied to `buckets.clickhouse.name` only,
and the 1Password item titled `<cluster>-cloudflare-clickhouse_backup`.

The server reads the key into its environment at start, so a rotated key
takes effect only after `kubectl -n plausible rollout restart statefulset
clickhouse`, a restart of a minute or so.

## `<cluster>-plausible-secret_key_base` and `<cluster>-plausible-totp_vault_key`

The two keys Plausible derives everything from: dashboard sessions and
e-mail tokens from the first, the encryption of every user's 2FA secret from
the second. Both become keys of `plausible` in the `plausible` namespace,
along with the Postgres URL composed from `<cluster>-postgres-plausible`.

1. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-plausible-secret_key_base`
2. Into **credential**, paste the `SECRET_KEY_BASE` the instance already runs
   with. For a brand new instance, `openssl rand -base64 48`
3. Again for `<cluster>-plausible-totp_vault_key`, with `TOTP_VAULT_KEY`, or
   `openssl rand -base64 32` for a new instance

Changing either logs everyone out, and changing the second locks every user
with 2FA out for good. Rotation is not a thing here, so these items are
written once. The pod reads them at start:
`kubectl -n plausible rollout restart deployment plausible`.

## `<cluster>-maxmind-plausible_analytics`

MaxMind license key Plausible downloads the GeoLite2 City database with at
every start, for city and region on the dashboard instead of country alone.
Becomes `MAXMIND_LICENSE_KEY` in the `plausible` Secret.

1. Go to [MaxMind](https://www.maxmind.com/en/accounts/current/license-key)
   → **Manage License Keys** → **Generate new license key**
2. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-maxmind-plausible_analytics`, paste the key into **credential**

Plausible reads it at start, so a rotated key takes effect after
`kubectl -n plausible rollout restart deployment plausible`.

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

## `<cluster>-remark42-secret`

The key remark42 signs every session cookie with. Becomes `SECRET` in
`remark42-credentials` in the `remark42` namespace, as do the four items
below, each under the variable it names.

The GitHub, Google and Slack apps below each take the remark42 logo, the 512
px square `site/static/android-chrome-512x512.png` in its repo:

```
curl -sLo remark42-logo.png https://raw.githubusercontent.com/umputun/remark42/master/site/static/android-chrome-512x512.png
```

1. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-remark42-secret`
2. Into **credential**, paste `openssl rand -base64 64 | tr -d '\n'`

Nothing on disk is encrypted with it, so rotation is safe: every commenter is
signed out once, and an anonymous commenter gets their identity back by typing
the same name. remark42 reads this whole group at start, so a rotated value
takes effect only after `kubectl -n remark42 rollout restart deployment
remark42`.

## `<cluster>-github-remark42_oauth`

The GitHub OAuth app commenters sign in with. Becomes `AUTH_GITHUB_CID` from
**username** and `AUTH_GITHUB_CSEC` from **credential**.

1. Go to [GitHub](https://github.com/settings/developers) → **OAuth Apps** →
   **New OAuth App**
2. Set **Application name** (e.g. `Remark42`), **Homepage URL** to
   `https://remark42.<zone>`, and **Redirect URI** to
   `https://remark42.<zone>/auth/github/callback`
3. **Register application**
4. Under **Application logo**, **Upload new logo** → pick `remark42-logo.png`
   → **Set new application logo**
5. **Generate a new client secret**, then copy it. GitHub shows the secret
   only once
6. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-github-remark42_oauth`
7. Set **username** to the **Client ID**, and paste the client secret into
   **credential**

User IDs derive from the GitHub account, not the app, so a replacement app
keeps every existing commenter and the admins in `settings.admin.sharedId`.

## `<cluster>-google-remark42_oauth`

The Google OAuth client commenters sign in with. Becomes `AUTH_GOOGLE_CID`
from **username** and `AUTH_GOOGLE_CSEC` from **credential**.

1. Go to [Google Cloud console](https://console.cloud.google.com) → create a
   project, or pick one, then **APIs & Services** → **OAuth consent screen**
2. Pick [**Branding**](https://console.cloud.google.com/auth/branding) and
   fill the form:
   - **App name**: `Remark42`
   - **User support email**: The dropdown only offers the account's own addresses
   - **App logo**: `remark42-logo.png`. Google shows it on the consent
     screen only after brand verification, sign-in works either way
   - **Application home page**: `https://remark42.<zone>/web/`
   - **Application privacy policy link**:
     `https://remark42.<zone>/web/privacy.html`
   - **Authorized domain 1**: `<zone>`
   - **Developer contact information**: Your email address

   Save with no scopes, then **Publish app** so people outside the test list
   can sign in

3. [**Clients**](https://console.cloud.google.com/auth/clients) →
   **Create client** and fill the form:
   - **Application type**: `Web application`
   - **Name**: `<cluster>-google-remark42_oauth`, the 1Password item's title,
     so the two find each other. Not shown to end users
   - **Authorized JavaScript origins**, URIs 1: `https://remark42.<zone>`
   - **Authorized redirect URIs**, URIs 1:
     `https://remark42.<zone>/auth/google/callback`

   **Create**. The settings can take from five minutes to a few hours to
   take effect

4. Copy the **Client ID** and **Client secret** now. Google hides the secret
   once the dialog closes
5. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-google-remark42_oauth`
6. Set **username** to the client ID, and paste the client secret into
   **credential**

## `<cluster>-slack-remark42_notify`

The bot token admin notifications post to Slack with. Becomes
`NOTIFY_SLACK_TOKEN`. The channel is `settings.notify.slack.channel` in
`apps/values/remark42.yaml.gotmpl`, not a secret.

1. Go to [Slack API](https://api.slack.com/apps) → **Create New App** →
   **From an app manifest**, pick the workspace, and paste this as the
   manifest.

   ```json
   {
     "display_information": {
       "background_color": "#2056b4",
       "description": "Comment engine",
       "name": "Remark42"
     },
     "features": {
       "bot_user": {
         "always_online": false,
         "display_name": "Remark42"
       }
     },
     "oauth_config": {
       "scopes": {
         "bot": ["chat:write", "chat:write.public", "channels:read"]
       }
     }
   }
   ```

2. **Next**, then **Create and Install** → **Allow** → **Go to App Settings**
3. **Basic Information** → under **Display Information**, **Add App Icon**
   → pick `remark42-logo.png`. 512 px is the minimum Slack accepts, which
   this file meets exactly
4. Under **Install App**, copy the **Bot User OAuth Token**, the one starting with `xoxb-`
5. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-slack-remark42_notify`, paste the token into **credential**

## `<cluster>-mailcow-remark42`

The mailbox remark42 sends reply notifications and e-mail verifications from,
over SMTP. Becomes `SMTP_USERNAME` from **username** and `SMTP_PASSWORD` from
**credential**. The same address is `settings.notify.email.fromAddress` and
`settings.admin.sharedEmail` in the values file.

1. In the mailcow web UI at `https://mailcow.<zone>/admin/mailbox` → **Add mailbox** with Username: `remark@<zone>` if it does not exist, then **Login** as it
2. **App passwords** → **Create app password**
3. Name it (e.g. `<cluster>-mailcow-remark42`)
4. Tick **SMTP** only. Leave IMAP, POP3, EAS, DAV and Sieve unticked: the
   pod can then send mail and nothing else → **Add**
5. In 1Password, in `Develop`: **New Item** → **API Credential**, title
   `<cluster>-mailcow-remark42`
6. Set **username** to `remark@<zone>`, and paste the app password into
   **credential**
