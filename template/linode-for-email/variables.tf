variable "name" {
  type        = string
  description = "The Linode's display label"
}

variable "region" {
  type        = string
  description = "Region the Linode is deployed in. Full list at https://api.linode.com/v4/regions"
}

variable "type" {
  type        = string
  description = "Linode plan defining CPU, RAM and disk. Full list at https://api.linode.com/v4/linode/types"
}

variable "private_ip" {
  type        = bool
  description = "Enable private networking. Linode can enable this on a live instance but never disable it"
  default     = false
}

variable "backups_enabled" {
  type        = bool
  description = "Enrol the Linode in the paid Backup service"
  default     = false
}

variable "hostname" {
  type        = string
  description = "Fully qualified name for the instance, used for both forward records and both PTRs (e.g. mailcow.tomy.me)"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a fully qualified domain name in lower case."
  }
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone holding the forward records"
}

variable "image" {
  type        = string
  description = "Image to deploy on creation. Full list at https://api.linode.com/v4/images"
  default     = null
}

variable "authorized_users" {
  type        = list(string)
  description = "Linode usernames whose profile SSH keys are added to root on creation. Required alongside image, and empty for an adopted instance"
  default     = []
}

variable "mailcow_version" {
  type        = string
  description = "mailcow-dockerized release tag cloud-init installs on first boot (e.g. 2026-09a). Null skips the bootstrap, for an adopted instance"
  default     = null
}

variable "timezone" {
  type        = string
  description = "TZ for mailcow, as in Asia/Taipei"
  default     = "Etc/UTC"
}

variable "mail_domain" {
  type        = string
  description = "Domain whose MX, SPF, DMARC, DKIM and autodiscovery records point at this host. Null creates none"
  default     = null
}

variable "dkim_selector" {
  type        = string
  description = "DKIM selector mailcow signs with, from Configuration → ARC/DKIM keys"
  default     = null
}

variable "dkim_public_key" {
  type        = string
  description = "The p= value of that key, as mailcow shows it"
  default     = null
}

variable "dmarc_rua" {
  type        = list(string)
  description = "Addresses aggregate DMARC reports go to"
  default     = []
}

variable "tlsa_spki_sha256" {
  type        = string
  description = "SHA-256 of the mail certificate's public key for the DANE TLSA record (3 1 1): openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256. Null creates none"
  default     = null
}
