output "alb_dns_name" {
  description = "Public DNS name of the ALB (API entry point)"
  value       = module.ecs_service.alb_dns_name
}

output "tenant_data_bucket" {
  description = "S3 bucket name for tenant data"
  value       = module.s3_app.bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the API container image"
  value       = module.ecr.repository_url
}

output "api_task_role_arn" {
  description = "ARN of the API Task Role"
  value       = module.iam_api.task_role_arn
}

output "deploy_role_arn" {
  description = "ARN of the Deploy Role"
  value       = module.iam_cross_account.deploy_role_arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs_service.service_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.db_endpoint
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN attached to the ALB"
  value       = module.waf.web_acl_arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = module.posture.guardduty_detector_id
}

output "access_analyzer_arn" {
  description = "IAM Access Analyzer ARN"
  value       = module.posture.access_analyzer_arn
}
