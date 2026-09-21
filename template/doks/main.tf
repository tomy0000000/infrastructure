##################################################
# DOKS cluster
##################################################

# This will convert "1.36." into "1.36.3" (or whatever the latest patch is) at plan time
data "digitalocean_kubernetes_versions" "this" {
  version_prefix = var.version_prefix
}

resource "digitalocean_kubernetes_cluster" "this" {
  name    = var.name
  region  = var.region
  version = data.digitalocean_kubernetes_versions.this.latest_version

  ha            = var.ha
  auto_upgrade  = var.auto_upgrade
  surge_upgrade = true

  tags = var.tags

  node_pool {
    name       = "${var.name}-nodepool"
    size       = var.node_size
    auto_scale = true
    min_nodes  = var.node_min
    max_nodes  = var.node_max
    tags       = var.tags
  }

  lifecycle {
    # The autoscaler owns the live node count, so every scaling event would
    # otherwise read as drift.
    ignore_changes = [node_pool[0].node_count]
  }
}
