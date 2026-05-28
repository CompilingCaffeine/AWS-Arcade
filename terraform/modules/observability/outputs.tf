output "audit_bucket_id" {
  description = "Audit logs bucket name."
  value       = aws_s3_bucket.audit.id
}

output "audit_bucket_arn" {
  description = "Audit logs bucket ARN."
  value       = aws_s3_bucket.audit.arn
}

output "alarm_topic_arn" {
  description = "SNS topic for CloudWatch alarms."
  value       = aws_sns_topic.alarms.arn
}

output "trail_name" {
  description = "CloudTrail trail name."
  value       = aws_cloudtrail.this.name
}
