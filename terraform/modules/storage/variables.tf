variable "name_prefix" {
  description = "Prefix used for S3 bucket names."
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to destroy non-empty buckets."
  type        = bool
  default     = false
}

variable "upload_retention_days" {
  description = "Number of days before uploaded ZIPs expire."
  type        = number
  default     = 30
}

variable "enable_access_logging" {
  description = "Whether to deliver S3 server access logs to access_logs_bucket."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "Bucket receiving S3 server access logs. Required when enable_access_logging=true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

