variable "tenant_data_bucket_arn" {
  description = "ARN of the S3 tenant data bucket"
  type        = string
}

variable "tenant_a_secret_arn" {
  description = "ARN of Tenant A API key secret"
  type        = string
}

variable "tenant_b_secret_arn" {
  description = "ARN of Tenant B API key secret"
  type        = string
}

variable "tenant_c_secret_arn" {
  description = "ARN of Tenant C API key secret"
  type        = string
}

variable "rds_secret_arn" {
  description = "ARN of the RDS credentials secret"
  type        = string
}
