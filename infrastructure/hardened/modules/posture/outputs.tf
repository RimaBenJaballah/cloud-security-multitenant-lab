output "guardduty_detector_id" {
  value = aws_guardduty_detector.this.id
}

output "access_analyzer_arn" {
  value = aws_accessanalyzer_analyzer.account.arn
}
