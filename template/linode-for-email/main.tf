##################################################
# Linode instance
##################################################

resource "linode_instance" "this" {
  label  = var.name
  region = var.region
  type   = var.type

  image            = var.image
  authorized_users = var.authorized_users

  private_ip      = var.private_ip
  backups_enabled = var.backups_enabled

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      image,
      root_pass,
      authorized_keys,
      authorized_users,
      stackscript_id,
      backup_id,
      # Provider-side defaults that the API never returns for an adopted instance.
      migration_type,
      resize_disk,
    ]
  }
}

locals {
  # ip_address is deprecated, so pick the public address out of the ipv4 set.
  # Linode allocates private addresses from 192.168.128.0/17.
  public_ipv4 = one([for ip in linode_instance.this.ipv4 : ip if !startswith(ip, "192.168.")])

  # First address of the routed range, carrying both the AAAA and the PTR.
  ipv6_address = "${linode_ipv6_range.this.range}1"
}

resource "linode_ipv6_range" "this" {
  linode_id     = linode_instance.this.id
  prefix_length = 64
}

# Linode refuses a PTR until the matching forward record already resolves, so
# each RDNS record waits on the record that makes it valid.
resource "linode_rdns" "v4" {
  address            = local.public_ipv4
  rdns               = var.hostname
  wait_for_available = true

  depends_on = [cloudflare_dns_record.a]
}

resource "linode_rdns" "v6" {
  address            = local.ipv6_address
  rdns               = var.hostname
  wait_for_available = true

  depends_on = [cloudflare_dns_record.aaaa]
}

##################################################
# Cloudflare DNS records
##################################################

# Validate that the hostname is inside the zone
data "cloudflare_zone" "this" {
  zone_id = var.zone_id

  lifecycle {
    postcondition {
      condition     = self.name == var.hostname || endswith(var.hostname, ".${self.name}")
      error_message = "hostname ${var.hostname} is not inside the zone this module was given (${self.name})."
    }
  }
}

resource "cloudflare_dns_record" "a" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"
  comment = var.name
  content = local.public_ipv4
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "aaaa" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "AAAA"
  comment = var.name
  content = local.ipv6_address
  ttl     = 1
  proxied = false
}
