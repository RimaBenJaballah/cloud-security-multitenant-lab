output "cloudtrail_local_log_group_arn" {
  value = aws_cloudwatch_log_group.cloudtrail_local.arn
}

output "cloudtrail_local_log_group_name" {
  value = aws_cloudwatch_log_group.cloudtrail_local.name
}

output "cloudtrail_logs_role_arn" {
  value = aws_iam_role.cloudtrail_logs.arn
}
