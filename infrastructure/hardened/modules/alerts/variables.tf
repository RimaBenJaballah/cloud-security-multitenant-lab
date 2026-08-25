variable "alerting_log_group_name" {
  description = "CloudWatch log group that receives forwarded CloudTrail events"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications. Leave empty to create the topic without an email subscription."
  type        = string
  default     = ""
}
