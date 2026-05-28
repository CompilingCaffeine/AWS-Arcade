output "upload_bucket_name" {
  description = "S3 bucket where game ZIPs are uploaded."
  value       = module.storage.upload_bucket_id
}

output "site_bucket_name" {
  description = "Private S3 bucket containing deployed frontend and game files."
  value       = module.storage.site_bucket_id
}

output "catalog_table_name" {
  description = "DynamoDB game catalog table."
  value       = module.catalog.table_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.cdn.distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront generated domain name."
  value       = module.cdn.distribution_domain_name
}

output "portfolio_url" {
  description = "Public portfolio URL."
  value       = var.enable_custom_domain && length(var.domain_names) > 0 ? "https://${var.domain_names[0]}/" : "https://${module.cdn.distribution_domain_name}/"
}

output "upload_command_example" {
  description = "Example command for uploading a game ZIP."
  value       = "aws s3 cp /tmp/sample-game.zip s3://${module.storage.upload_bucket_id}/incoming/sample-game.zip"
}

output "audit_bucket_name" {
  description = "Shared audit logs bucket name."
  value       = module.observability.audit_bucket_id
}

output "alarm_topic_arn" {
  description = "SNS topic for CloudWatch alarm notifications."
  value       = module.observability.alarm_topic_arn
}

output "lambda_dlq_url" {
  description = "Dead-letter queue URL for failed package processor invocations."
  value       = module.lambda_pipeline.dlq_url
}

output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = module.auth.user_pool_id
}

output "user_pool_issuer" {
  description = "Cognito User Pool OIDC issuer URL."
  value       = module.auth.user_pool_issuer
}

output "web_client_id" {
  description = "Cognito web client ID for the Hosted UI / SPA."
  value       = module.auth.web_client_id
}

output "hosted_ui_login_url" {
  description = "Cognito Hosted UI login URL pre-filled for the portfolio callback."
  value       = module.auth.hosted_ui_login_url
}

output "api_endpoint" {
  description = "HTTP API base URL. POST {api_endpoint}/uploads with a Cognito JWT to get a presigned URL."
  value       = module.api.api_endpoint
}

