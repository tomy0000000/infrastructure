variable "account_id" {
  type        = string
  description = "Cloudflare account ID"
}

variable "zone_id" {
  type        = string
  description = "Zone the WebFinger route belongs to"
}

variable "name" {
  type        = string
  description = "Worker script name, unique within the account"
}

variable "domain" {
  type        = string
  description = "Zone apex serving /.well-known/webfinger and owning the acct: addresses"
}

variable "issuer" {
  type        = string
  description = "OIDC issuer URL returned for every acct: address in the domain"
}
