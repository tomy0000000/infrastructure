variable "name" {
  type        = string
  description = "The cluster's display name, also used as the node pool prefix"
}

variable "region" {
  type        = string
  description = "Region the cluster is deployed in, see https://docs.digitalocean.com/platform/regional-availability/ (e.g. sfo3)"
}

variable "version_prefix" {
  type        = string
  description = "Kubernetes minor version to pin to, trailing dot included (e.g. 1.36.)."

  validation {
    condition     = can(regex("^1\\.[0-9]+\\.$", var.version_prefix))
    error_message = "version_prefix must be a minor version ending in a dot, e.g. 1.36., otherwise 1.3 would also match 1.30 and 1.31."
  }
}

variable "ha" {
  type        = bool
  description = "Replicated control plane with a 99.95% SLA, cannot be disabled once enabled"
  default     = false
}

variable "auto_upgrade" {
  type        = bool
  description = "Apply patch releases during its maintenance window."
  default     = true
}

variable "node_size" {
  type        = string
  description = "Droplet plan for the worker nodes, see https://slugs.do-api.dev/ (e.g. s-2vcpu-4gb)"
}

variable "node_min" {
  type        = number
  description = "Floor the node pool autoscales down to"
}

variable "node_max" {
  type        = number
  description = "Ceiling the node pool autoscales up to"
}

variable "tags" {
  type        = list(string)
  description = "Tags applied to both the cluster and its node pool"
  default     = []
}
