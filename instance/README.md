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
