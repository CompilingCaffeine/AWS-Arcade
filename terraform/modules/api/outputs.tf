output "api_endpoint" {
  description = "Default invoke URL for the HTTP API."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "function_name" {
  description = "presign Lambda function name."
  value       = module.presign.function_name
}

output "function_arn" {
  description = "presign Lambda function ARN."
  value       = module.presign.function_arn
}

output "my_uploads_function_name" {
  description = "my_uploads Lambda function name."
  value       = module.my_uploads.function_name
}

output "admin_handler_function_name" {
  description = "admin_handler Lambda function name."
  value       = module.admin_handler.function_name
}
