output "tenant_a_secret_arn" {
  value = aws_secretsmanager_secret.tenant_a.arn
}

output "tenant_b_secret_arn" {
  value = aws_secretsmanager_secret.tenant_b.arn
}

output "tenant_c_secret_arn" {
  value = aws_secretsmanager_secret.tenant_c.arn
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}
