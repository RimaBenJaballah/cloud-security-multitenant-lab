variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "prod_account_id" {
  description = "AWS Account ID of the prod account"
  type        = string
}

variable "dev_account_id" {
  description = "AWS Account ID of the dev account"
  type        = string
}

variable "security_account_id" {
  description = "AWS Account ID of the security account"
  type        = string
}

variable "cloudtrail_s3_bucket_name" {
  description = "CloudTrail S3 bucket name in the security account (from security outputs)"
  type        = string

  validation {
    condition     = var.cloudtrail_s3_bucket_name != "CHANGE_ME_FROM_SECURITY_OUTPUT"
    error_message = "Set cloudtrail_s3_bucket_name from environments/security terraform output before applying prod."
  }
}

variable "logs_destination_arn" {
  description = "CloudWatch Logs Destination ARN in the security account (from security outputs)"
  type        = string

  validation {
    condition     = var.logs_destination_arn != "CHANGE_ME_FROM_SECURITY_OUTPUT"
    error_message = "Set logs_destination_arn from environments/security terraform output before applying prod."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, formatted as owner/repo"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository)) && var.github_repository != "<your-github-username>/cloud-security-multitenant-lab"
    error_message = "Set github_repository to your real GitHub repo, for example: rima/cloud-security-app-phase2."
  }
}

variable "github_branch" {
  description = "GitHub branch allowed to deploy"
  type        = string
  default     = "main"
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

variable "waf_rate_limit" {
  description = "Maximum requests per 5-minute window per source IP"
  type        = number
  default     = 1000
}
