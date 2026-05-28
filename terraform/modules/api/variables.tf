variable "name_prefix" {
  description = "Name prefix for API resources."
  type        = string
}

variable "source_dir" {
  description = "Source directory for the request-upload-url Lambda."
  type        = string
}

variable "upload_bucket_name" {
  description = "Upload bucket name. Used in presigned URL generation."
  type        = string
}

variable "upload_bucket_arn" {
  description = "Upload bucket ARN. Used for Lambda IAM s3:PutObject scope."
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito web client ID. Used as the JWT audience."
  type        = string
}

variable "cognito_issuer" {
  description = "Cognito User Pool issuer URL. Used by the JWT authorizer."
  type        = string
}

variable "allowed_origins" {
  description = "CORS allowed origins for the API."
  type        = list(string)
}

variable "presigned_url_ttl_seconds" {
  description = "TTL for presigned upload URLs."
  type        = number
  default     = 900
}

variable "max_upload_bytes" {
  description = "Advisory upload size limit returned to clients (enforcement is in package_processor)."
  type        = number
  default     = 52428800
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for API access logs and the Lambda."
  type        = number
  default     = 365
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
