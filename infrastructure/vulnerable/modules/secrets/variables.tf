variable "rds_host" {
  description = "RDS instance hostname"
  type        = string
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
  default     = "dbadmin"
}

variable "rds_password" {
  description = "RDS master password (generated at environment level)"
  type        = string
  sensitive   = true
}
