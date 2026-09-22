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
