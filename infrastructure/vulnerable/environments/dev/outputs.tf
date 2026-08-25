output "pipeline_user_arn" {
  description = "ARN of the pipeline IAM user"
  value       = module.iam_pipeline_user.user_arn
}

output "pipeline_user_access_key_id" {
  description = "Access Key ID for the pipeline IAM user (lab use only)"
  value       = module.iam_pipeline_user.access_key_id
  sensitive   = true
}

output "pipeline_user_secret_access_key" {
  description = "Secret Access Key for the pipeline IAM user (lab use only)"
  value       = module.iam_pipeline_user.secret_access_key
  sensitive   = true
}
