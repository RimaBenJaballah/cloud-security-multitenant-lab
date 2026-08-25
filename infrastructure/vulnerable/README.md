# Cloud Security Lab — Terraform

Production-ready Terraform code for a multi-account AWS security lab with
intentional misconfigurations for attack-surface analysis.

## Prerequisites

- **Windows 11** with Terraform >= 1.5 and AWS CLI v2 installed
- An AWS management account with an IAM user `terraform-bootstrap` that has
  `AdministratorAccess`
- AWS CLI profile configured:
  ```
  aws configure --profile sec-lab-bootstrap
  ```

## Project Structure

```
terraform/
├── modules/                        Reusable building blocks
│   ├── network/                    VPC, subnets, IGW, NAT, route tables, 3 security groups
│   ├── ecr/                        ECR repository
│   ├── s3_app/                     S3 tenant data bucket (versioning off, no isolation)
│   ├── database/                   RDS PostgreSQL + DB subnet group
│   ├── secrets/                    4 Secrets Manager secrets (3 tenant keys + RDS creds)
│   ├── ecs_cluster/                ECS cluster + container log group
│   ├── ecs_service/                ALB + target group + listener + task def + ECS service
│   ├── iam_api/                    API Task Role (misconfigured) + Execution Role
│   ├── iam_cross_account/          Deploy Role (misconfigured) + Developer + Break-glass
│   ├── iam_pipeline_user/          IAM user + static access key (misconfiguration)
│   ├── logging_prod/               CloudTrail + local log group + subscription filter
│   ├── logging_security/           CloudTrail S3 bucket + Logs Destination + Audit Role
│   └── alerts/                     3 metric filters + 3 CloudWatch alarms
│
└── environments/                   Root modules — one per account
    ├── management/                 AWS Organization + 3 member accounts
    ├── security/                   Calls: logging_security, alerts
    ├── dev/                        Calls: iam_pipeline_user
    └── prod/                       Calls: all remaining modules
```

## Deployment Order

Each environment is an independent Terraform root module. Apply them in
sequence — later environments depend on outputs from earlier ones.

### Step 1 — Management (create the 3 accounts)

Edit `environments/management/terraform.tfvars` with three unique email
addresses, then:

```powershell
cd environments\management
terraform init
terraform apply
```

Copy the three account IDs from the output.

### Step 2 — Security (alerting infrastructure)

Paste the account IDs into `environments/security/terraform.tfvars`, then:

```powershell
cd ..\security
terraform init
terraform apply
```

Copy `cloudtrail_s3_bucket_name` and `logs_destination_arn` from the output.

### Step 3 — Dev (pipeline IAM user)

Paste the account IDs into `environments/dev/terraform.tfvars`, then:

```powershell
cd ..\dev
terraform init
terraform apply
```

### Step 4 — Prod (application infrastructure)

Paste all account IDs plus the two security outputs into
`environments/prod/terraform.tfvars`, then:

```powershell
cd ..\prod
terraform init
terraform apply
```

The `container_image` variable defaults to a public nginx placeholder. After
pushing your Flask app image to ECR, uncomment and set it in
`terraform.tfvars`:

```hcl
container_image = "<account_id>.dkr.ecr.eu-west-3.amazonaws.com/sec-lab-api:latest"
```

Then re-apply:

```powershell
terraform apply
```

## Teardown

Destroy in reverse order:

```powershell
cd environments\prod     && terraform destroy
cd ..\dev                && terraform destroy
cd ..\security           && terraform destroy
cd ..\management         && terraform destroy
```

## Intentional Misconfigurations

| # | Resource | Misconfiguration | Attack Path |
|---|----------|-----------------|-------------|
| 1 | ECS Security Group | Outbound: all traffic to 0.0.0.0/0 (should be TCP 443 + TCP 5432 only) | Path 1 |
| 2 | API Task Role | `s3:*` on entire bucket (no tenant prefix scoping) | Path 1 |
| 3 | S3 Bucket | No tenant isolation via bucket policy; versioning disabled | Path 1 |
| 4 | Deploy Role trust policy | No conditions (no MFA, no IP restriction) | Path 2 |
| 5 | Deploy Role permissions | `secretsmanager:GetSecretValue` on `*` (unrestricted) | Path 2 |
| 6 | IAM User | Static credentials instead of OIDC federation | Path 2 |

## Design Decisions

1. **RDS password generated at environment level** — The `database` module
   needs the password as input and the `secrets` module needs the RDS
   hostname as input. To break this circular dependency, the
   `random_password` is created in `environments/prod/main.tf` and passed
   to both modules.

2. **CloudTrail Logs Role lives in `logging_prod`** — Not in
   `iam_cross_account`, because it is a service role (not cross-account)
   and the logging module needs its ARN to configure the trail. Keeping it
   together avoids a circular dependency.

3. **ALB folded into `ecs_service`** — The ALB, target group, listener, and
   ECS service are tightly coupled. Splitting them would create circular
   references (service → target group → VPC, listener → ALB).

4. **Placeholder container image** — `public.ecr.aws/nginx/nginx:alpine`
   so infrastructure can be provisioned before the Flask app exists.

5. **`recovery_window_in_days = 0`** on Secrets Manager — allows immediate
   deletion during `terraform destroy`. Lab only.

6. **`force_destroy = true`** on S3 buckets — deletes non-empty buckets on
   destroy. Lab only.

7. **RDS `skip_final_snapshot = true`** — no snapshot on destroy.

8. **Single NAT Gateway** — single-AZ trade-off per PDF spec.

9. **No remote backend** — all environments use local state per
   requirements. The PDF's Terraform state backend (S3 + DynamoDB in
   security account) is intentionally omitted.

10. **RDS engine version** — PostgreSQL 16.4; adjust if your region offers
    a different minor version.

11. **Logs Destination IAM role** — Not in the PDF but required for the
    CloudWatch Logs Destination to write to the alerting log group. Created
    as `sec-lab-logs-destination-role-security`.

12. **`iam:PassRole`** on Deploy Role — required so the CI/CD pipeline can
    register new ECS task definitions that reference the API Task Role and
    Execution Role.
