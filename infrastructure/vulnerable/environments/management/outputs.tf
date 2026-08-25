output "dev_account_id" {
  description = "Account ID of the dev account"
  value       = aws_organizations_account.dev.id
}

output "prod_account_id" {
  description = "Account ID of the prod account"
  value       = aws_organizations_account.prod.id
}

output "security_account_id" {
  description = "Account ID of the security account"
  value       = aws_organizations_account.security.id
}
