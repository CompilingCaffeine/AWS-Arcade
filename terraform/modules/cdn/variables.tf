variable "name_prefix" {
  description = "Name prefix for CloudFront resources."
  type        = string
}

variable "site_bucket_id" {
  description = "Site S3 bucket name."
  type        = string
}

variable "site_bucket_regional_domain_name" {
  description = "Site S3 regional domain name."
  type        = string
}

variable "aliases" {
  description = "CloudFront aliases."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for aliases."
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

