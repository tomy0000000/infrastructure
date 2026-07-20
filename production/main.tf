locals {
  # Core
  environment = "production"

  # R2 buckets
  buckets = yamldecode(file("${path.module}/config.yaml")).buckets
}

module "r2_img" {
  source = "../template/r2"

  account_id  = var.cloudflare_account_id
  bucket_name = local.buckets.img.name
  location    = local.buckets.img.location
}

module "r2_misc" {
  source = "../template/r2"

  account_id  = var.cloudflare_account_id
  bucket_name = local.buckets.misc.name
  location    = local.buckets.misc.location
}
