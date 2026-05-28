variable "hosted_zone_name" {
  description = "Route53 public hosted zone name."
  type        = string
}

variable "domain_names" {
  description = "Domain names for the CloudFront certificate."
  type        = list(string)
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

