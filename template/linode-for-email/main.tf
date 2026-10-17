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

  # cloud-init bootstrap, read once by the Metadata service on first boot.
  dynamic "metadata" {
    for_each = var.mailcow_version == null ? [] : [1]
    content {
      user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
        mailcow_version = var.mailcow_version
        hostname        = var.hostname
        timezone        = var.timezone
      }))
    }
  }

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      # First-boot inputs. Changing either would otherwise replace the instance.
      image,
      metadata,
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

# Only mail, its web UI and SSH may reach the host, whatever is listening on it.
resource "linode_firewall" "this" {
  label           = var.name
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "mail-and-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,25,80,110,143,443,465,587,993,995,4190"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # Path MTU discovery and IPv6 neighbour discovery need unsolicited ICMP in.
  inbound {
    label    = "icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  linodes = [linode_instance.this.id]
}

locals {
  # ip_address is deprecated, so pick the public address out of the ipv4 set.
  # Linode allocates private addresses from 192.168.128.0/17.
  public_ipv4 = one([for ip in linode_instance.this.ipv4 : ip if !startswith(ip, "192.168.")])

  # First address of the routed range for the AAAA and PTR, canonicalised because the API may spell it with leading zeros.
  ipv6_address = cidrhost("${linode_ipv6_range.this.range}/${linode_ipv6_range.this.prefix_length}", 1)
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

# DANE pins the public key, which mailcow's ACME client keeps across renewals.
resource "cloudflare_dns_record" "tlsa" {
  count = var.tlsa_spki_sha256 == null ? 0 : 1

  zone_id = var.zone_id
  name    = "_25._tcp.${var.hostname}"
  type    = "TLSA"
  comment = var.name
  ttl     = 1
  proxied = false
  data = {
    usage         = 3
    selector      = 1
    matching_type = 1
    certificate   = var.tlsa_spki_sha256
  }
}

##################################################
# Mail domain records, when this host is the MX
##################################################

locals {
  mail = var.mail_domain == null ? {} : { (var.mail_domain) = true }

  # Cloudflare stores a TXT longer than 255 characters as quoted 255-character chunks, so match that or the plan never settles.
  dkim_txt = "v=DKIM1;k=rsa;t=s;s=email;p=${var.dkim_public_key}"
  dkim_content = join(" ", [
    for i in range(0, length(local.dkim_txt), 255) : "\"${substr(local.dkim_txt, i, min(255, length(local.dkim_txt) - i))}\""
  ])
}

resource "cloudflare_dns_record" "mx" {
  for_each = local.mail

  zone_id  = var.zone_id
  name     = each.key
  type     = "MX"
  comment  = var.name
  content  = var.hostname
  priority = 10
  ttl      = 1
  proxied  = false
}

resource "cloudflare_dns_record" "spf" {
  for_each = local.mail

  zone_id = var.zone_id
  name    = each.key
  type    = "TXT"
  comment = var.name
  content = "\"v=spf1 mx -all\""
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "dmarc" {
  for_each = local.mail

  zone_id = var.zone_id
  name    = "_dmarc.${each.key}"
  type    = "TXT"
  comment = var.name
  content = "\"v=DMARC1; p=reject; rua=${join(",", [for a in var.dmarc_rua : "mailto:${a}"])}\""
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "dkim" {
  for_each = local.mail

  zone_id = var.zone_id
  name    = "${var.dkim_selector}._domainkey.${each.key}"
  type    = "TXT"
  comment = var.name
  content = local.dkim_content
  ttl     = 1
  proxied = false
}

# Thunderbird and Outlook find the IMAP and SMTP settings through these.
resource "cloudflare_dns_record" "autoconfig" {
  for_each = local.mail

  zone_id = var.zone_id
  name    = "autoconfig.${each.key}"
  type    = "CNAME"
  comment = var.name
  content = var.hostname
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "autodiscover" {
  for_each = local.mail

  zone_id = var.zone_id
  name    = "autodiscover.${each.key}"
  type    = "CNAME"
  comment = var.name
  content = var.hostname
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "autodiscover_srv" {
  for_each = local.mail

  zone_id  = var.zone_id
  name     = "_autodiscover._tcp.${each.key}"
  type     = "SRV"
  comment  = var.name
  priority = 0
  ttl      = 1
  proxied  = false
  data = {
    priority = 0
    weight   = 1
    port     = 443
    target   = var.hostname
  }
}
