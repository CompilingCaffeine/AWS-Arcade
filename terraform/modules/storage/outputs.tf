output "upload_bucket_id" {
  description = "Uploads bucket name."
  value       = aws_s3_bucket.uploads.id
}

output "upload_bucket_arn" {
  description = "Uploads bucket ARN."
  value       = aws_s3_bucket.uploads.arn
}

output "site_bucket_id" {
  description = "Site bucket name."
  value       = aws_s3_bucket.site.id
}

output "site_bucket_arn" {
  description = "Site bucket ARN."
  value       = aws_s3_bucket.site.arn
}

output "site_bucket_regional_domain_name" {
  description = "Regional domain name for the site bucket."
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}

