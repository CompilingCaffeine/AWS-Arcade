variable "name_prefix" {
  description = "Name prefix for observability resources."
  type        = string
}

variable "account_id" {
  description = "AWS account ID owning the audit resources."
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region."
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
