data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}
