output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "developer_role_arn" {
  value = aws_iam_role.developer.arn
}

output "breakglass_role_arn" {
  value = aws_iam_role.breakglass.arn
}
