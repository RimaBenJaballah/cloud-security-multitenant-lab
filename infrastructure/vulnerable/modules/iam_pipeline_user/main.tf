###############################################################################
# IAM User — CI/CD pipeline identity
# MISCONFIGURATION: uses static IAM user instead of OIDC federation
###############################################################################

resource "aws_iam_user" "this" {
  name = "sec-lab-pipeline-user-dev"
}

resource "aws_iam_user_policy" "assume_deploy" {
  name = "assume-deploy-role"
  user = aws_iam_user.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.prod_account_id}:role/sec-lab-deploy-role-prod"
      }
    ]
  })
}

# MISCONFIGURATION — static access keys; in a real breach these get
# hardcoded into the GitHub Actions pipeline config and committed to git
resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}
