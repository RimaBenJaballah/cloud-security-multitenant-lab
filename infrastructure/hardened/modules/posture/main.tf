###############################################################################
# AWS-native security posture and threat detection controls
###############################################################################

resource "aws_guardduty_detector" "this" {
  enable = true
}

resource "aws_securityhub_account" "this" {
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "sec-lab-access-analyzer-prod"
  type          = "ACCOUNT"
}
