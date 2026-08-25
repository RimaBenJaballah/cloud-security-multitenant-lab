# Cloud Security Project — Phase 2 Terraform (Hardened)

This folder is the Phase 2 secured Terraform version of the project. It keeps the same general structure and resource naming convention as Phase 1, but removes the intentional vulnerabilities and adds selected cloud security controls.

## Important deployment model

This Terraform is for **Option B**:

- Phase 1 Terraform code remains saved locally as evidence.
- Phase 1 AWS resources must be destroyed before Phase 2 is applied.
- Phase 2 reuses the same AWS accounts and same resource names.
- Phase 2 application should live in a new clean GitHub repository.

## What changed from Phase 1

### Application support in infrastructure

- ECS no longer hardcodes the old S3 bucket name, RDS endpoint, or Secrets Manager ARN suffix.
- ECS receives bucket name, DB host, and secret ARN from Terraform module outputs.
- The task definition no longer falls back to `:latest`. It uses a `:bootstrap` placeholder until CI/CD deploys a commit-SHA image.

### IAM hardening

- API Task Role no longer has `s3:*`.
- API Task Role only has `s3:ListBucket`, `s3:GetObject`, and `s3:PutObject` for known tenant prefixes.
- Deploy Role no longer has `secretsmanager:GetSecretValue` on `*`.
- Deploy Role is assumed through GitHub OIDC, not an IAM user with static keys.
- `iam:PassRole` is restricted to the ECS task role and execution role.

### Network hardening

- ECS security group no longer allows all outbound traffic.
- ECS can only use TCP 443 outbound and TCP 5432 to the RDS security group.

### Storage hardening

- S3 versioning is enabled on the tenant data bucket.
- S3 Block Public Access remains enabled.
- Bucket policy denies insecure transport.
- Bucket policy denies object actions outside known tenant prefixes.

### Detection and posture

- F5 is fixed permanently in Terraform: Lambda permission uses `prod_account_id` as `source_account`.
- Existing CloudTrail metric filters remain.
- SNS topic is added for alarm notifications.
- GuardDuty is enabled.
- Security Hub with AWS Foundational Security Best Practices is enabled.
- IAM Access Analyzer is enabled.
- WAF is attached to the ALB with managed rules and rate limiting.

## Before you apply

Edit these values first:

1. `environments/security/terraform.tfvars`
   - Optional: set `alert_email` and confirm the SNS email.

2. `environments/prod/terraform.tfvars`
   - Set `cloudtrail_s3_bucket_name` from `terraform output` in `environments/security`.
   - Set `logs_destination_arn` from `terraform output` in `environments/security`.
   - Set `github_repository` to your new Phase 2 app repo, for example: `yourname/cloud-security-app-phase2`.

## Suggested apply order

```bash
# 1) Keep management environment unless you really need to recreate accounts.

# 2) Security first
cd environments/security
terraform init
terraform validate
terraform plan
terraform apply
terraform output

# 3) Copy cloudtrail_s3_bucket_name and logs_destination_arn into environments/prod/terraform.tfvars

# 4) Dev is intentionally empty in Phase 2, but can still be applied for documentation
cd ../dev
terraform init
terraform validate
terraform plan
terraform apply

# 5) Prod
cd ../prod
terraform init
terraform validate
terraform plan
terraform apply
```

## Important note about the first ECS deployment

The first full prod apply creates the ECS service with a `:bootstrap` image placeholder. After the Phase 2 app repo is ready, GitHub Actions should deploy a commit-SHA image and update the ECS service.

Do not use `:latest` in Phase 2.
