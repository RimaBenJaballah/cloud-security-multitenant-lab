variable "dev_account_id" {
  description = "AWS Account ID of the dev account"
  type        = string
}

variable "prod_account_id" {
  description = "AWS Account ID of the prod account"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the API Task Role (for iam:PassRole in Deploy Role)"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS Task Execution Role (for iam:PassRole in Deploy Role)"
  type        = string
}
