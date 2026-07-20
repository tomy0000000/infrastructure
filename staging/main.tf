locals {
  # Core
  environment = "staging"

  # R2 image bucket
  r2_img_bucket   = "tomy-img-staging"
  r2_img_location = "APAC"

  # R2 misc bucket
  r2_misc_bucket   = "tomy-misc-staging"
  r2_misc_location = "APAC"
}

module "r2_img" {
  source = "../template/r2"

  account_id  = var.cloudflare_account_id
  bucket_name = local.r2_img_bucket
  location    = local.r2_img_location
}

module "r2_misc" {
  source = "../template/r2"

  account_id  = var.cloudflare_account_id
  bucket_name = local.r2_misc_bucket
  location    = local.r2_misc_location
}
