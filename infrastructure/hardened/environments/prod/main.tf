###############################################################################
# RDS password — generated here to break the circular dependency between
# the database module (needs password) and secrets module (needs RDS host)
###############################################################################

resource "random_password" "rds" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

###############################################################################
# Security posture controls — Phase 2 added baseline
###############################################################################

module "posture" {
  source = "../../modules/posture"

  region = var.region
}

###############################################################################
# Networking
###############################################################################

module "network" {
  source = "../../modules/network"

  region = var.region
}

###############################################################################
# ECR Repository
###############################################################################

module "ecr" {
  source = "../../modules/ecr"
}

###############################################################################
# S3 Tenant Data Bucket
###############################################################################

module "s3_app" {
  source = "../../modules/s3_app"
}

###############################################################################
# ECS Cluster + Container Log Group
###############################################################################

module "ecs_cluster" {
  source = "../../modules/ecs_cluster"
}

###############################################################################
# RDS PostgreSQL
###############################################################################

module "database" {
  source = "../../modules/database"

  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.network.rds_sg_id
  db_password        = random_password.rds.result
}

###############################################################################
# Secrets Manager (tenant API keys + RDS credentials)
###############################################################################

module "secrets" {
  source = "../../modules/secrets"

  rds_host     = module.database.db_address
  rds_password = random_password.rds.result
}

###############################################################################
# IAM — API Task Role + ECS Task Execution Role
###############################################################################

module "iam_api" {
  source = "../../modules/iam_api"

  tenant_data_bucket_arn = module.s3_app.bucket_arn
  tenant_a_secret_arn    = module.secrets.tenant_a_secret_arn
  tenant_b_secret_arn    = module.secrets.tenant_b_secret_arn
  tenant_c_secret_arn    = module.secrets.tenant_c_secret_arn
  rds_secret_arn         = module.secrets.rds_secret_arn
}

###############################################################################
# GitHub OIDC provider for CI/CD
###############################################################################

module "oidc_github" {
  source = "../../modules/oidc_github"
}

###############################################################################
# IAM — Cross-account roles (Deploy via GitHub OIDC, Developer, Break-glass)
###############################################################################

module "iam_cross_account" {
  source = "../../modules/iam_cross_account"

  dev_account_id           = var.dev_account_id
  prod_account_id          = var.prod_account_id
  github_oidc_provider_arn = module.oidc_github.provider_arn
  github_repository        = var.github_repository
  github_branch            = var.github_branch
  ecr_repository_arn       = module.ecr.repository_arn
  task_role_arn            = module.iam_api.task_role_arn
  execution_role_arn       = module.iam_api.execution_role_arn
}

###############################################################################
# ECS Service + ALB
###############################################################################

module "ecs_service" {
  source = "../../modules/ecs_service"

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.network.alb_sg_id
  ecs_sg_id          = module.network.ecs_sg_id
  cluster_id         = module.ecs_cluster.cluster_id
  task_role_arn      = module.iam_api.task_role_arn
  execution_role_arn = module.iam_api.execution_role_arn
  container_image    = var.container_image
  ecr_repository_url = module.ecr.repository_url
  s3_bucket_name     = module.s3_app.bucket_name
  db_host            = module.database.db_address
  rds_secret_arn     = module.secrets.rds_secret_arn
  log_group_name     = module.ecs_cluster.log_group_name
  region             = var.region
}

###############################################################################
# WAF on the public ALB
###############################################################################

module "waf" {
  source = "../../modules/waf"

  alb_arn    = module.ecs_service.alb_arn
  rate_limit = var.waf_rate_limit
}

###############################################################################
# CloudTrail + Subscription Filter
###############################################################################

module "logging_prod" {
  source = "../../modules/logging_prod"

  cloudtrail_s3_bucket_name = var.cloudtrail_s3_bucket_name
  tenant_data_bucket_arn    = module.s3_app.bucket_arn
  logs_destination_arn      = var.logs_destination_arn
}
