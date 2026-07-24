variable "account_id" {
  type        = string
  description = "Cloudflare account ID"
}

variable "bucket_name" {
  type        = string
  description = "Full name of the R2 bucket (include env suffix, e.g. assets-staging)"
}

variable "location" {
  type        = string
  description = "Optional R2 location hint (e.g. WNAM, ENAM, APAC)"
  default     = null
}

variable "access_hosts" {
  type        = list(string)
  description = "Origins allowed to GET objects via CORS. Empty means no CORS resource is managed"
  default     = []
}

variable "bucket_hosts" {
  type = list(object({
    domain  = string
    zone_id = string
  }))
  description = "Custom domains serving the bucket, each with the zone it belongs to. Empty means none is managed"
  default     = []
}
