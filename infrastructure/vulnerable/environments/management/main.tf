###############################################################################
# AWS Organization
###############################################################################

resource "aws_organizations_organization" "this" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
  ]
  feature_set = "ALL"
}

###############################################################################
# Member Accounts
###############################################################################

resource "aws_organizations_account" "dev" {
  name      = "sec-lab-dev"
  email     = var.dev_account_email
  role_name = "OrganizationAccountAccessRole"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "prod" {
  name      = "sec-lab-prod"
  email     = var.prod_account_email
  role_name = "OrganizationAccountAccessRole"

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "security" {
  name      = "sec-lab-security"
  email     = var.security_account_email
  role_name = "OrganizationAccountAccessRole"

  lifecycle {
    ignore_changes = [role_name]
  }
}
