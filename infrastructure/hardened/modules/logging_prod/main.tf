###############################################################################
# CloudWatch Log Group — CloudTrail local (same-account, prod)
###############################################################################

resource "aws_cloudwatch_log_group" "cloudtrail_local" {
  name              = "/aws/cloudtrail/sec-lab-prod-trail-local"
  retention_in_days = 30

  tags = { Name = "/aws/cloudtrail/sec-lab-prod-trail-local" }
}

###############################################################################
# CloudTrail CloudWatch Logs Role — writes CT events to local log group
###############################################################################

resource "aws_iam_role" "cloudtrail_logs" {
  name = "sec-lab-cloudtrail-logs-role-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_logs_write" {
  name = "cloudtrail-logs-write"
  role = aws_iam_role.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail_local.arn}:*"
      }
    ]
  })
}

###############################################################################
# CloudTrail Trail
###############################################################################

resource "aws_cloudtrail" "this" {
  name                       = "sec-lab-trail-prod"
  s3_bucket_name             = var.cloudtrail_s3_bucket_name
  is_multi_region_trail      = true
  enable_log_file_validation = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_local.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # S3 data events on tenant data bucket only (required for Path 1 detection)
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${var.tenant_data_bucket_arn}/"]
    }
  }

  tags = { Name = "sec-lab-trail-prod" }
}

###############################################################################
# Subscription Filter — forwards CloudTrail events to security account
###############################################################################

resource "aws_cloudwatch_log_subscription_filter" "to_security" {
  name            = "sec-lab-cloudtrail-subscription-prod"
  log_group_name  = aws_cloudwatch_log_group.cloudtrail_local.name
  destination_arn = var.logs_destination_arn
  filter_pattern  = ""

  depends_on = [aws_cloudtrail.this]
}
