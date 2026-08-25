###############################################################################
# Random values for tenant API keys
###############################################################################

resource "random_password" "tenant_a" {
  length  = 40
  special = false
}

resource "random_password" "tenant_b" {
  length  = 40
  special = false
}

resource "random_password" "tenant_c" {
  length  = 40
  special = false
}

###############################################################################
# Secrets Manager secrets
###############################################################################

resource "aws_secretsmanager_secret" "tenant_a" {
  name                    = "tenant-a/api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tenant_a" {
  secret_id     = aws_secretsmanager_secret.tenant_a.id
  secret_string = random_password.tenant_a.result
}

resource "aws_secretsmanager_secret" "tenant_b" {
  name                    = "tenant-b/api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tenant_b" {
  secret_id     = aws_secretsmanager_secret.tenant_b.id
  secret_string = random_password.tenant_b.result
}

resource "aws_secretsmanager_secret" "tenant_c" {
  name                    = "tenant-c/api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "tenant_c" {
  secret_id     = aws_secretsmanager_secret.tenant_c.id
  secret_string = random_password.tenant_c.result
}

resource "aws_secretsmanager_secret" "rds" {
  name                    = "rds/credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username = var.rds_username
    password = var.rds_password
    host     = var.rds_host
    port     = 5432
    dbname   = "tenantdb"
  })
}
