locals {
  # Core
  environment = "production"
  config      = yamldecode(file("${path.module}/config.yaml"))

  # Cloudflare zones
  zones = local.config.zones

  # R2 buckets
  buckets = local.config.buckets
}

module "zone_main" {
  source = "../template/zone"

  account_id = var.cloudflare_account_id
  domain     = local.zones.main
}

module "r2_img" {
  source = "../template/r2"

  account_id   = var.cloudflare_account_id
  bucket_name  = local.buckets.img.name
  location     = local.buckets.img.location
  access_hosts = local.buckets.img.access_hosts
  bucket_hosts = [for host in local.buckets.img.bucket_hosts : {
    domain  = host
    zone_id = module.zone_main.zone_id
  }]
}

module "r2_misc" {
  source = "../template/r2"

  account_id  = var.cloudflare_account_id
  bucket_name = local.buckets.misc.name
  location    = local.buckets.misc.location
}
