variable "name_prefix" {
  description = "Name prefix for Lambda pipeline resources."
  type        = string
}

variable "source_dir" {
  description = "Local directory containing Lambda source code."
  type        = string
}

variable "schema_file" {
  description = "Path to manifest JSON Schema bundled with the Lambda package."
  type        = string
}

variable "frontend_source_dir" {
  description = "Local directory containing static frontend files."
  type        = string
}

variable "frontend_destination_bucket_id" {
  description = "S3 bucket where frontend files should be uploaded."
  type        = string
}

variable "upload_bucket_arn" {
  description = "Upload bucket ARN."
  type        = string
}

variable "site_bucket_arn" {
  description = "Site bucket ARN."
  type        = string
}

variable "site_bucket_name" {
  description = "Site bucket name."
  type        = string
}

variable "catalog_table_arn" {
  description = "Catalog DynamoDB table ARN."
  type        = string
}

variable "catalog_table_name" {
  description = "Catalog DynamoDB table name."
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  type        = string
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  type        = string
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 120
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
