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
  description = "Full ECR image URI for the Flask API. Empty uses a non-latest bootstrap tag until CI/CD deploys a SHA image."
  type        = string
  default     = ""

  validation {
    condition     = var.container_image == "" || !can(regex(":latest$", var.container_image))
    error_message = "Do not use the mutable :latest tag in Phase 2. Use a commit SHA tag."
  }
}

variable "ecr_repository_url" {
  description = "ECR repository URL used to build the bootstrap image URI"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name passed as env var to container"
  type        = string
}

variable "db_host" {
  description = "RDS endpoint hostname passed as env var to container"
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
