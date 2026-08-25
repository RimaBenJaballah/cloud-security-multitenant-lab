###############################################################################
# Random suffix for globally unique S3 bucket name
###############################################################################

resource "random_id" "suffix" {
  byte_length = 4
}

###############################################################################
# CloudTrail S3 Bucket (long-term audit archive)
###############################################################################

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "sec-lab-cloudtrail-logs-security-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudTrailGetBucketAcl"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-3:${var.prod_account_id}:trail/sec-lab-trail-prod"
          }
        }
      },
      {
        Sid       = "AllowCloudTrailPutObject"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.prod_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-3:${var.prod_account_id}:trail/sec-lab-trail-prod"
          }
        }
      }
    ]
  })
}

###############################################################################
# CloudWatch Log Group - alerting (receives forwarded CloudTrail events)
###############################################################################

resource "aws_cloudwatch_log_group" "alerting" {
  name              = "/aws/cloudtrail/sec-lab-prod-trail"
  retention_in_days = 30
}

###############################################################################
# Lambda Forwarder - receives events from Logs Destination, writes to
# alerting log group. Required because a Logs Destination cannot target
# a CloudWatch Log Group directly (only Lambda, Kinesis, or Firehose).
###############################################################################

data "archive_file" "forwarder" {
  type        = "zip"
  source_file = "${path.module}/lambda/forwarder.py"
  output_path = "${path.module}/lambda/forwarder.zip"
}

resource "aws_iam_role" "lambda_forwarder" {
  name = "sec-lab-cloudtrail-forwarder-role-security"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_forwarder_logs" {
  name = "write-to-alerting-log-group"
  role = aws_iam_role.lambda_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.alerting.arn,
          "${aws_cloudwatch_log_group.alerting.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:eu-west-3:${var.security_account_id}:log-group:/aws/lambda/sec-lab-cloudtrail-forwarder-security:*"
      }
    ]
  })
}

resource "aws_lambda_function" "forwarder" {
  filename         = data.archive_file.forwarder.output_path
  source_code_hash = data.archive_file.forwarder.output_base64sha256
  function_name    = "sec-lab-cloudtrail-forwarder-security"
  role             = aws_iam_role.lambda_forwarder.arn
  handler          = "forwarder.handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.alerting.name
    }
  }
}

# Allow CloudWatch Logs to invoke the Lambda (from the Logs Destination)
resource "aws_lambda_permission" "allow_logs" {
  statement_id   = "AllowCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.forwarder.function_name
  principal      = "logs.eu-west-3.amazonaws.com"
  source_account = var.prod_account_id
}

###############################################################################
# IAM Role for CloudWatch Logs Destination (invokes Lambda)
###############################################################################

resource "aws_iam_role" "logs_destination" {
  name = "sec-lab-logs-destination-role-security"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "logs.eu-west-3.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "logs_destination_invoke" {
  name = "invoke-forwarder-lambda"
  role = aws_iam_role.logs_destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.forwarder.arn
      }
    ]
  })
}

###############################################################################
# CloudWatch Logs Destination (receives events from prod subscription filter)
# Targets the Lambda forwarder, which writes to the alerting log group.
###############################################################################

resource "aws_cloudwatch_log_destination" "from_prod" {
  name       = "sec-lab-cloudtrail-destination-security"
  role_arn   = aws_iam_role.logs_destination.arn
  target_arn = aws_lambda_function.forwarder.arn

  depends_on = [
    aws_iam_role_policy.logs_destination_invoke,
    aws_lambda_permission.allow_logs
  ]
}

resource "aws_cloudwatch_log_destination_policy" "from_prod" {
  destination_name = aws_cloudwatch_log_destination.from_prod.name

  access_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowProdAccountToPush"
        Effect    = "Allow"
        Principal = { AWS = var.prod_account_id }
        Action    = "logs:PutSubscriptionFilter"
        Resource  = aws_cloudwatch_log_destination.from_prod.arn
      }
    ]
  })
}

###############################################################################
# Logging / Audit Role
###############################################################################

resource "aws_iam_role" "audit" {
  name = "sec-lab-audit-role-security"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.security_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = {
          Bool = { "aws:MultiFactorAuthPresent" = "true" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "audit_readonly" {
  name = "audit-read-only"
  role = aws_iam_role.audit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudtrail:LookupEvents",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:DescribeTrails",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}
