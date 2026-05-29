output "sender_email" {
  description = "Verified SES sender."
  value       = aws_ses_email_identity.sender.email
}

output "sender_identity_arn" {
  description = "SES identity ARN for IAM scoping of ses:SendEmail."
  value       = "arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/${aws_ses_email_identity.sender.email}"
}
