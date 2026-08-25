output "alarm_arns" {
  value = [
    aws_cloudwatch_metric_alarm.unexpected_assume_deploy_role.arn,
    aws_cloudwatch_metric_alarm.task_role_direct_s3.arn,
    aws_cloudwatch_metric_alarm.deploy_role_secrets_read.arn,
  ]
}
