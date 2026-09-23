# Environment Variables

Instructions for setting up environment variables.

Each environment has its own file (`staging.env`, `production.env`), loaded by
mise when `MISE_ENV` is set:

```sh
export MISE_ENV=staging   # loads instance/staging.env via mise.staging.toml
```

These files hold credentials and are gitignored. Verify with `echo $ENVIRONMENT`.

## `CLOUDFLARE_API_TOKEN`

API token the Terraform Cloudflare provider uses.

1. Go to [Cloudflare dashboard](https://dash.cloudflare.com) → profile icon
   (top right) → **Profile** → **API Tokens**
2. Click **Create Token** → **Create Custom Token**
3. Name it (e.g. `Infrastructure Staging`) and add the permissions:
   - **Account** → **Workers R2 Storage** → **Edit** (R2 buckets)
   - **Zone** → **Zone** → **Edit** (zones)
   - **Zone** → **DNS** → **Edit** (the A and AAAA records fronting each instance)
4. Scope it to a specific account under **Account Resources**
5. **Continue to summary** → **Create Token**

An existing token can be edited in place to add a missing permission, so there
is no need to issue a new one and update both env files.

## `DIGITALOCEAN_TOKEN`

Personal access token the Terraform DigitalOcean provider uses, and the same
token the kubeconfig embeds for cluster access.

1. Go to [DigitalOcean control panel](https://cloud.digitalocean.com) → **Account** in the left sidebar → **API** → **Tokens** tab
2. Click **Generate New Token**
3. Name it (e.g. `Infrastructure Staging`) and pick an expiry
4. Grant **Full Access**, or custom scopes covering `kubernetes` and
   `load_balancer` read and write
5. **Generate Token**, then copy it right away. DigitalOcean shows the value
   only once

A cluster's kubeconfig authenticates as this token, so revoking it also cuts
`kubectl` access until `mise run kubeconfig <env>` is run against a new one.

## `LINODE_TOKEN`

Personal access token the Terraform Linode provider uses.

1. Go to [Linode Cloud Manager](https://cloud.linode.com) → profile icon
   (top right) → **My Profile** → **API Tokens**
2. Click **Create a Personal Access Token**
3. Label it (e.g. `Infrastructure Staging`) and pick an expiry
4. Leave every scope at **No Access** except:
   - **Linodes** → **Read/Write** (the instances themselves)
   - **IPs** → **Read/Write** (reverse DNS and IPv6 ranges)
5. **Create Token**, then copy it right away. Linode shows the value only once

Reverse DNS and IPv6 ranges live under `/networking/`, which the **Linodes**
scope does not cover. A token without **IPs** can still read an instance and its
addresses, so the gap only surfaces when Terraform tries to set a PTR or
allocate a range.

Linode cannot change the scopes of an existing personal access token, so
widening access means creating a replacement and revoking the old one.

## `TF_VAR_cloudflare_account_id`

Cloudflare account ID where resources are created.

1. Go to [Cloudflare dashboard](https://dash.cloudflare.com)
2. Copy the 32-character hex ID from the URL right after `dash.cloudflare.com/`,
   or find it under any zone's **Overview** page in the right sidebar as
   **Account ID**

## `ONE_PASSWORD_ESO_SERVICE_ACCOUNT_TOKEN`

1Password Service Account token that External Secrets Operator uses to fetch
every workload Secret. `mise run charts <env> apply` reads it from this file
and hands it to the cluster once, as the operator's bootstrap Secret.

1. Go to [1Password](https://my.1password.com) → **Developer** in the left
   sidebar → **Service Accounts** → **New Service Account**
2. Name it (e.g. `ESO Production`)
3. Grant access to the **Develop** vault only, **Read** only
4. Under **Environment access**, leave every environment at **No Access**.
   ESO reads items from the vault, and 1Password Environments are a separate
   feature it does not use
5. **Create Account**, then copy the token right away. 1Password shows the
   value only once

A service account cannot be modified after creation. Widening or narrowing
its access means revoking it and creating a replacement, then updating this
variable.

The name is deliberately not `OP_SERVICE_ACCOUNT_TOKEN`. The `op` CLI honors
that variable itself, so it would switch every `op` call in this shell to the
service account, including the 1Password plugin behind `doctl`.

The Family plan allows 1,000 reads per hour per token and 1,000 reads per day
across the whole account, which is why ExternalSecrets refresh hourly.
