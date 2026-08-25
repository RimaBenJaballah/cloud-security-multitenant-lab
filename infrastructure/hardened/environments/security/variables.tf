variable "security_account_id" {
  description = "AWS Account ID of the security account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID of the prod account"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications. Leave empty to skip email subscription."
  type        = string
  default     = ""
}
