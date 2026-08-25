###############################################################################
# Logging infrastructure (CloudTrail bucket, Logs Destination, Audit Role)
###############################################################################

module "logging_security" {
  source = "../../modules/logging_security"

  prod_account_id     = var.prod_account_id
  security_account_id = var.security_account_id
}

###############################################################################
# Alerting (metric filters + alarms + SNS email notifications)
###############################################################################

module "alerts" {
  source = "../../modules/alerts"

  alerting_log_group_name = module.logging_security.alerting_log_group_name
  alert_email             = var.alert_email
}
