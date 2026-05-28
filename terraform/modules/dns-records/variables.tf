variable "hosted_zone_name" {
  description = "Route53 public hosted zone name."
  type        = string
}

variable "domain_names" {
  description = "Domain names that should alias to CloudFront."
  type        = list(string)
}

variable "distribution_domain_name" {
  description = "CloudFront distribution domain name."
  type        = string
}

variable "distribution_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID."
  type        = string
}

