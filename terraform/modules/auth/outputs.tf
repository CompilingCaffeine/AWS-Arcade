output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_issuer" {
  description = "Cognito User Pool OIDC issuer URL (for JWT verification)."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "web_client_id" {
  description = "Web client ID used by the Hosted UI and SPA."
  value       = aws_cognito_user_pool_client.web.id
}

output "hosted_ui_domain" {
  description = "Cognito Hosted UI domain (without scheme)."
  value       = "${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "hosted_ui_login_url" {
  description = "Pre-built Hosted UI login URL for the first configured callback."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com/login?response_type=code&client_id=${aws_cognito_user_pool_client.web.id}&scope=openid+email+profile&redirect_uri=${var.callback_urls[0]}"
}

output "admins_group_name" {
  description = "Name of the admins user group."
  value       = aws_cognito_user_group.admins.name
}
