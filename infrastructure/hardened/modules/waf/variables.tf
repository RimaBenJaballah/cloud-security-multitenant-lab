variable "alb_arn" {
  description = "ARN of the ALB to protect"
  type        = string
}

variable "rate_limit" {
  description = "Maximum requests per 5-minute window per source IP"
  type        = number
  default     = 1000
}
