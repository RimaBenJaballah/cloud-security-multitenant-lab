output "cloudtrail_s3_bucket_name" {
  value = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_s3_bucket_arn" {
  value = aws_s3_bucket.cloudtrail.arn
}

output "logs_destination_arn" {
  description = "CloudWatch Logs Destination ARN - used by the prod subscription filter"
  value       = aws_cloudwatch_log_destination.from_prod.arn
}

output "alerting_log_group_name" {
  value = aws_cloudwatch_log_group.alerting.name
}

output "alerting_log_group_arn" {
  value = aws_cloudwatch_log_group.alerting.arn
}
