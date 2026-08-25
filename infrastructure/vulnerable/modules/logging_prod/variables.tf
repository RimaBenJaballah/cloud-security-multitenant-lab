variable "cloudtrail_s3_bucket_name" {
  description = "Name of the CloudTrail S3 bucket in the security account"
  type        = string
}

variable "tenant_data_bucket_arn" {
  description = "ARN of the S3 tenant data bucket (for S3 data events)"
  type        = string
}

variable "logs_destination_arn" {
  description = "ARN of the CloudWatch Logs Destination in the security account"
  type        = string
}
