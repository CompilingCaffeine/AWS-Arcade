output "table_name" {
  description = "DynamoDB games table name (published catalog)."
  value       = aws_dynamodb_table.games.name
}

output "table_arn" {
  description = "DynamoDB games table ARN."
  value       = aws_dynamodb_table.games.arn
}

output "submissions_table_name" {
  description = "DynamoDB submissions table name (upload workflow + audit log)."
  value       = aws_dynamodb_table.submissions.name
}

output "submissions_table_arn" {
  description = "DynamoDB submissions table ARN."
  value       = aws_dynamodb_table.submissions.arn
}

