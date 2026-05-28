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

