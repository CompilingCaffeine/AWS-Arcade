output "function_name" {
  description = "Package processor Lambda name."
  value       = aws_lambda_function.package_processor.function_name
}

output "function_arn" {
  description = "Package processor Lambda ARN."
  value       = aws_lambda_function.package_processor.arn
}

output "role_arn" {
  description = "Package processor IAM role ARN."
  value       = aws_iam_role.package_processor.arn
}

