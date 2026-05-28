output "api_endpoint" {
  description = "Default invoke URL for the HTTP API."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.this.id
}

output "function_name" {
  description = "request-upload-url Lambda function name."
  value       = aws_lambda_function.request_upload_url.function_name
}

output "function_arn" {
  description = "request-upload-url Lambda function ARN."
  value       = aws_lambda_function.request_upload_url.arn
}
