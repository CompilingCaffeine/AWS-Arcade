variable "name_prefix" {
  description = "Name prefix for catalog resources."
  type        = string
}

variable "enable_pitr" {
  description = "Enable point-in-time recovery."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

