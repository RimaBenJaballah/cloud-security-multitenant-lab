###############################################################################
# API Task Role — application identity inside ECS container
# Hardened: least-privilege S3 access, no s3:* wildcard.
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

# The app still serves all tenants with one role, so IAM cannot know the
# request tenant. This policy removes admin/destructive S3 actions and only
# allows access under the known tenant prefixes.
resource "aws_iam_role_policy" "task_role_s3" {
  name = "s3-tenant-data-least-privilege"
  role = aws_iam_role.task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListKnownTenantPrefixes"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.tenant_data_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "tenant-a",
              "tenant-a/*",
              "tenant-b",
              "tenant-b/*",
              "tenant-c",
              "tenant-c/*"
            ]
          }
        }
      },
      {
        Sid    = "ReadWriteKnownTenantObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${var.tenant_data_bucket_arn}/tenant-a/*",
          "${var.tenant_data_bucket_arn}/tenant-b/*",
          "${var.tenant_data_bucket_arn}/tenant-c/*"
        ]
      }
    ]
  })
}

# Secrets Manager: read all three tenant API keys (intended — one app serves all tenants)
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
# ECS Task Execution Role — used by ECS agent
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
