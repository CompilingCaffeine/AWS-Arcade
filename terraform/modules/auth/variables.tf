variable "name_prefix" {
  description = "Name prefix for Cognito resources."
  type        = string
}

variable "project_display_name" {
  description = "Display name shown to users in Cognito verification emails."
  type        = string
  default     = "Herzi Arcade"
}

variable "cognito_domain_prefix" {
  description = "Cognito Hosted UI domain prefix. Must be globally unique. Empty falls back to name_prefix-auth."
  type        = string
  default     = ""
}

variable "callback_urls" {
  description = "Cognito Hosted UI OAuth callback URLs."
  type        = list(string)
}

variable "logout_urls" {
  description = "Cognito Hosted UI logout redirect URLs."
  type        = list(string)
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
