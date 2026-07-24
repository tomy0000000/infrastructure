resource "cloudflare_r2_bucket" "this" {
  account_id = var.account_id
  name       = var.bucket_name
  location   = var.location
}

resource "cloudflare_r2_bucket_cors" "this" {
  count = length(var.access_hosts) > 0 ? 1 : 0

  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  rules = [for host in var.access_hosts : {
    allowed = {
      methods = ["GET"]
      origins = [host]
    }
  }]
}

resource "cloudflare_r2_bucket_lifecycle" "this" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  rules = [{
    id         = "Auto abort stale upload"
    enabled    = true
    conditions = { prefix = "" }
    abort_multipart_uploads_transition = {
      condition = { type = "Age", max_age = 604800 } # 7 days
    }
  }]
}

resource "cloudflare_r2_custom_domain" "this" {
  for_each = { for host in var.bucket_hosts : host.domain => host }

  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  domain      = each.value.domain
  enabled     = true
  zone_id     = each.value.zone_id
}

# Keep the public r2.dev URL off
resource "cloudflare_r2_managed_domain" "this" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.this.name
  enabled     = false
}
