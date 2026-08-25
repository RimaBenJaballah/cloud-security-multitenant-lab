###############################################################################
# Deploy Role — assumed cross-account by CI/CD pipeline from dev
# MISCONFIGURATION #1: trust policy has NO conditions (no MFA, no IP)
# MISCONFIGURATION #2: secretsmanager:GetSecretValue on * (over-permissioning)
###############################################################################

resource "aws_iam_role" "deploy" {
  name = "sec-lab-deploy-role-prod"

  # MISCONFIGURATION — no conditions on trust policy
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.dev_account_id}:user/sec-lab-pipeline-user-dev" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Intended deployment permissions (ECR push + ECS update)
resource "aws_iam_role_policy" "deploy_permissions" {
  name = "deploy-permissions"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [
          var.task_role_arn,
          var.execution_role_arn,
        ]
      }
    ]
  })
}

# MISCONFIGURATION — secretsmanager:GetSecretValue on * (unrestricted)
resource "aws_iam_role_policy" "deploy_secrets_overperm" {
  name = "secrets-manager-over-permissioned"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# Developer Role — read-only access to prod (no misconfiguration)
###############################################################################

resource "aws_iam_role" "developer" {
  name = "sec-lab-developer-role-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.dev_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = {
          Bool = { "aws:MultiFactorAuthPresent" = "true" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "developer_readonly" {
  name = "developer-readonly"
  role = aws_iam_role.developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:Describe*",
          "ecs:List*",
          "logs:Get*",
          "logs:Describe*",
          "logs:FilterLogEvents",
          "cloudwatch:Get*",
          "cloudwatch:Describe*",
          "cloudwatch:List*",
          "s3:ListBucket",
          "s3:GetObject",
          "ecr:Describe*",
          "ecr:List*",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# Break-glass Admin — emergency full access (no misconfiguration)
###############################################################################

resource "aws_iam_role" "breakglass" {
  name = "sec-lab-breakglass-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.prod_account_id}:root" }
        Action    = "sts:AssumeRole"
        Condition = {
          Bool = { "aws:MultiFactorAuthPresent" = "true" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "breakglass_admin" {
  role       = aws_iam_role.breakglass.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
