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
   - **Account** → **Workers R2 Storage** → **Edit**
   - **Zone** → **Zone** → **Edit**
4. Scope it to a specific account under **Account Resources**
5. **Continue to summary** → **Create Token**

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
   - **Linodes** → **Read/Write**
5. **Create Token**, then copy it right away. Linode shows the value only once

## `TF_VAR_cloudflare_account_id`

Cloudflare account ID where resources are created.

1. Go to [Cloudflare dashboard](https://dash.cloudflare.com)
2. Copy the 32-character hex ID from the URL right after `dash.cloudflare.com/`,
   or find it under any zone's **Overview** page in the right sidebar as
   **Account ID**
