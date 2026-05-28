variable "project_name" {
  description = "Project name used for backend resource names."
  type        = string
  default     = "game-publishing-platform"
}

variable "aws_region" {
  description = "AWS region for Terraform state resources."
  type        = string
  default     = "us-west-2"
}

variable "force_destroy_state_bucket" {
  description = "Allow Terraform to destroy the state bucket. Keep false for production."
  type        = bool
  default     = false
}

