variable "function_name" {
  description = "Full Lambda function name (the caller decides naming + length budget)."
  type        = string
}

variable "source_dir" {
  description = "Source directory archived into the Lambda zip."
  type        = string
}

variable "handler" {
  description = "Lambda handler entry point."
  type        = string
  default     = "handler.handler"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.13"
}

variable "memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "environment_variables" {
  description = "Lambda environment variables."
  type        = map(string)
  default     = {}
}

variable "iam_statements" {
  description = <<-DESC
    Extra IAM statements granted to the Lambda role beyond the always-on
    CloudWatch Logs + X-Ray statements. Each statement supports an optional
    list of conditions.
  DESC
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

variable "api_id" {
  description = "HTTP API ID."
  type        = string
}

variable "api_execution_arn" {
  description = "HTTP API execution ARN, used for the lambda:InvokeFunction permission scope."
  type        = string
}

variable "authorizer_id" {
  description = "JWT authorizer ID attached to every route this endpoint declares."
  type        = string
}

variable "routes" {
  description = "Route keys (e.g., \"POST /uploads\") attached to this Lambda. All routes share the JWT authorizer."
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
