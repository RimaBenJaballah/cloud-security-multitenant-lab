output "cloudtrail_s3_bucket_name" {
  description = "CloudTrail audit archive S3 bucket name (needed by prod)"
  value       = module.logging_security.cloudtrail_s3_bucket_name
}

output "logs_destination_arn" {
  description = "CloudWatch Logs Destination ARN (needed by prod)"
  value       = module.logging_security.logs_destination_arn
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = module.alerts.sns_topic_arn
}
