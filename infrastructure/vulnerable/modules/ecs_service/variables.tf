variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_sg_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "task_role_arn" {
  description = "IAM role ARN for the ECS task (application identity)"
  type        = string
}

variable "execution_role_arn" {
  description = "IAM role ARN for the ECS task execution (agent identity)"
  type        = string
}

variable "container_image" {
  description = "Container image URI. Defaults to nginx placeholder if empty."
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name passed as env var to container"
  type        = string
}

variable "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials (injected as container secret)"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for container logs"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}
