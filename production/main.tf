locals {
  # Core
  environment = "production"
  config      = yamldecode(file("${path.module}/config.yaml"))

  # Cloudflare zones
  zones = local.config.zones

  # R2 buckets
  buckets = local.config.buckets

  # DOKS cluster
  kubernetes = local.config.kubernetes

  # Linode instances
  instances = local.config.instances
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

module "doks" {
  source = "../template/doks"

  name           = local.kubernetes.name
  region         = local.kubernetes.region
  version_prefix = local.kubernetes.version_prefix
  ha             = local.kubernetes.ha
  auto_upgrade   = local.kubernetes.auto_upgrade
  node_size      = local.kubernetes.node.size
  node_min       = local.kubernetes.node.min
  node_max       = local.kubernetes.node.max
  tags           = [local.environment]
}

module "linode_mailcow" {
  source = "../template/linode-for-email"

  name             = local.instances.mailcow.name
  region           = local.instances.mailcow.region
  type             = local.instances.mailcow.type
  private_ip       = local.instances.mailcow.private_ip
  backups_enabled  = local.instances.mailcow.backups_enabled
  hostname         = local.instances.mailcow.hostname
  zone_id          = module.zone_main.zone_id
  image            = local.instances.mailcow.image
  authorized_users = local.instances.mailcow.authorized_users
}
