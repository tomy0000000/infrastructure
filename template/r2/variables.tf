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
