output "state_bucket_name" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table for Terraform state locking."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_hcl" {
  description = "Example backend.hcl content for terraform/envs/prod."
  value       = <<EOT
bucket         = "${aws_s3_bucket.terraform_state.id}"
key            = "prod/terraform.tfstate"
region         = "${var.aws_region}"
dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
use_lockfile   = true
encrypt        = true
EOT
}

