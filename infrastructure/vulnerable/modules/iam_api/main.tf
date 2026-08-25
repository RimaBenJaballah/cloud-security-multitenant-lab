###############################################################################
# API Task Role — application identity inside ECS container
# MISCONFIGURATION: s3:* on entire bucket (over-permissioning)
###############################################################################

resource "aws_iam_role" "task_role" {
  name = "sec-lab-task-role-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# MISCONFIGURATION — s3:* on entire bucket, no tenant prefix scoping
resource "aws_iam_role_policy" "task_role_s3" {
  name = "s3-over-permissioned"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = [
          var.tenant_data_bucket_arn,
          "${var.tenant_data_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Secrets Manager: read all three tenant API keys (intended — single app serves all tenants)
resource "aws_iam_role_policy" "task_role_secrets" {
  name = "secrets-manager-tenant-keys"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [
          var.tenant_a_secret_arn,
          var.tenant_b_secret_arn,
          var.tenant_c_secret_arn,
        ]
      }
    ]
  })
}

###############################################################################
# ECS Task Execution Role — used by ECS agent (no misconfiguration)
###############################################################################

resource "aws_iam_role" "execution_role" {
  name = "sec-lab-execution-role-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_rds_secret" {
  name = "rds-credentials-read"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.rds_secret_arn
      }
    ]
  })
}
