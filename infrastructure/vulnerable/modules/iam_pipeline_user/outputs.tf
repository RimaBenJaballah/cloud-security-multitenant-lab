output "user_arn" {
  value = aws_iam_user.this.arn
}

output "access_key_id" {
  value     = aws_iam_access_key.this.id
  sensitive = true
}

output "secret_access_key" {
  value     = aws_iam_access_key.this.secret
  sensitive = true
}
