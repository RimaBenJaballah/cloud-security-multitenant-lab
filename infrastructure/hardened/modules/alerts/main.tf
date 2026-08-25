###############################################################################
# SNS notification channel for alarms
###############################################################################

resource "aws_sns_topic" "security_alerts" {
  name = "sec-lab-security-alerts-security"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

###############################################################################
# Metric Filters — detect suspicious CloudTrail patterns
###############################################################################

# (1) Unexpected AssumeRole on Deploy Role
resource "aws_cloudwatch_log_metric_filter" "unexpected_assume_deploy_role" {
  name           = "sec-lab-unexpected-assume-deploy-role"
  log_group_name = var.alerting_log_group_name

  pattern = <<-PATTERN
    { ($.eventName = "AssumeRole") && ($.requestParameters.roleArn = "*sec-lab-deploy-role-prod*") }
  PATTERN

  metric_transformation {
    name          = "UnexpectedAssumeDeployRole"
    namespace     = "SecLab/Detection"
    value         = "1"
    default_value = "0"
  }
}

# (2) API Task Role direct S3 access (outside ECS container)
resource "aws_cloudwatch_log_metric_filter" "task_role_direct_s3" {
  name           = "sec-lab-task-role-direct-s3-access"
  log_group_name = var.alerting_log_group_name

  pattern = <<-PATTERN
    { ($.eventSource = "s3.amazonaws.com") && ($.userIdentity.arn = "*sec-lab-task-role-prod*") && ($.sourceIPAddress != "*.amazonaws.com") }
  PATTERN

  metric_transformation {
    name          = "TaskRoleDirectS3Access"
    namespace     = "SecLab/Detection"
    value         = "1"
    default_value = "0"
  }
}

# (3) Deploy Role Secrets Manager reads
resource "aws_cloudwatch_log_metric_filter" "deploy_role_secrets_read" {
  name           = "sec-lab-deploy-role-secrets-read"
  log_group_name = var.alerting_log_group_name

  pattern = <<-PATTERN
    { ($.eventSource = "secretsmanager.amazonaws.com") && ($.eventName = "GetSecretValue") && ($.userIdentity.arn = "*sec-lab-deploy-role-prod*") }
  PATTERN

  metric_transformation {
    name          = "DeployRoleSecretsRead"
    namespace     = "SecLab/Detection"
    value         = "1"
    default_value = "0"
  }
}

###############################################################################
# CloudWatch Alarms + SNS notifications
###############################################################################

resource "aws_cloudwatch_metric_alarm" "unexpected_assume_deploy_role" {
  alarm_name          = "sec-lab-alarm-unexpected-assume-deploy-role"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnexpectedAssumeDeployRole"
  namespace           = "SecLab/Detection"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Unexpected AssumeRole call on the Deploy Role detected"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "task_role_direct_s3" {
  alarm_name          = "sec-lab-alarm-task-role-direct-s3"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "TaskRoleDirectS3Access"
  namespace           = "SecLab/Detection"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "API Task Role used for direct S3 access outside ECS container"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "deploy_role_secrets_read" {
  alarm_name          = "sec-lab-alarm-deploy-role-secrets-read"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DeployRoleSecretsRead"
  namespace           = "SecLab/Detection"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Deploy Role reading secrets from Secrets Manager"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  ok_actions          = [aws_sns_topic.security_alerts.arn]
}
