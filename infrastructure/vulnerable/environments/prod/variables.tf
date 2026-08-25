variable "prod_account_id" {
  description = "AWS Account ID of the prod account (from management outputs)"
  type        = string
}

variable "dev_account_id" {
  description = "AWS Account ID of the dev account (from management outputs)"
  type        = string
}

variable "security_account_id" {
  description = "AWS Account ID of the security account (from management outputs)"
  type        = string
}

variable "cloudtrail_s3_bucket_name" {
  description = "CloudTrail S3 bucket name in the security account (from security outputs)"
  type        = string
}

variable "logs_destination_arn" {
  description = "CloudWatch Logs Destination ARN in the security account (from security outputs)"
  type        = string
}

variable "container_image" {
  description = "Full ECR image URI for the Flask API. Leave empty to use nginx placeholder."
  type        = string
  default     = ""
}
