variable "dev_account_id" {
  description = "AWS Account ID of the dev account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID of the prod account"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider in the prod account"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, formatted as owner/repo"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the deploy role"
  type        = string
  default     = "main"
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository used by the API"
  type        = string
}

variable "task_role_arn" {
  description = "API Task Role ARN allowed for iam:PassRole"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN allowed for iam:PassRole"
  type        = string
}
