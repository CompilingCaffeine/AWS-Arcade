variable "name_prefix" {
  description = "Name prefix for observability resources."
  type        = string
}

variable "account_id" {
  description = "AWS account ID owning the audit resources."
  type        = string
}

variable "log_retention_days" {
  description = "Lifecycle expiration for audit logs in the shared bucket."
  type        = number
  default     = 90
}

variable "alarm_email" {
  description = "Email subscribed to the SNS alarm topic. Empty disables subscription."
  type        = string
  default     = ""
}

variable "trail_is_multi_region" {
  description = "Whether the CloudTrail trail captures events from every region."
  type        = bool
  default     = true
}

variable "trail_log_retention_days" {
  description = "CloudWatch Logs retention for CloudTrail events."
  type        = number
  default     = 365
}

variable "force_destroy" {
  description = "Allow Terraform to destroy the non-empty audit bucket."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
