variable "project_name" {
  description = "Project name used in AWS resource names and tags."
  type        = string
  default     = "game-publishing-platform"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "Primary AWS region."
  type        = string
  default     = "us-west-2"
}

variable "enable_custom_domain" {
  description = "Create ACM certificate and Route53 records for CloudFront aliases."
  type        = bool
  default     = false
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name, such as herzi.ai."
  type        = string
  default     = ""
}

variable "domain_names" {
  description = "CloudFront aliases, for example play.herzi.ai and games.herzi.ai."
  type        = list(string)
  default     = []
}

variable "cloudfront_price_class" {
  description = "CloudFront edge location price class."
  type        = string
  default     = "PriceClass_100"
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy non-empty platform buckets. Keep false in production."
  type        = bool
  default     = false
}

variable "lambda_memory_size" {
  description = "Package processor Lambda memory in MB."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Package processor Lambda timeout."
  type        = number
  default     = 120
}

variable "upload_retention_days" {
  description = "Number of days to retain uploaded ZIP files."
  type        = number
  default     = 30
}

variable "enable_catalog_pitr" {
  description = "Enable DynamoDB point-in-time recovery for the catalog."
  type        = bool
  default     = false
}

variable "audit_log_retention_days" {
  description = "Lifecycle retention for the audit logs bucket (CloudTrail + S3 access)."
  type        = number
  default     = 90
}

variable "alarm_email" {
  description = "Email address subscribed to the SNS alarm topic. Empty disables subscription."
  type        = string
  default     = ""
}

