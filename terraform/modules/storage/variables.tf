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

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

