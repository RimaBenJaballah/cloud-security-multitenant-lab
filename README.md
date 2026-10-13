# Cloud Security Lab — Multi-Tenant SaaS on AWS

**A deliberately vulnerable multi-tenant SaaS on AWS that I attack end to end, then rebuild securely with Terraform.**

![AWS](https://img.shields.io/badge/AWS-eu--west--3-232F3E?logo=amazonaws&logoColor=white)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)
![Python](https://img.shields.io/badge/App-Python%20%7C%20Flask-3776AB?logo=python&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker&logoColor=white)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions%20%2B%20OIDC-2088FF?logo=githubactions&logoColor=white)
![Focus](https://img.shields.io/badge/Focus-Cloud%20Security%20%7C%20Offensive%20%2B%20Defensive-critical)

I built a realistic multi-tenant data-ingestion platform on AWS across three accounts, ran two complete attacks against it, then rebuilt every layer to close them: application, network, IAM, CI/CD, storage, and detection. The exploit steps, the fixes as code, and the before/after evidence are all here.

### Highlights

Two attacks carried through to real impact. The first turns a single malicious file upload into stolen container credentials and a cross-tenant data breach. The second turns one leaked Git commit into full control of the production account.

A three-account AWS environment written as modular Terraform (dev, prod, and an isolated security account), with 15+ reusable modules covering networking, ECS, IAM, storage, and logging.

A cross-account detection pipeline that I actually verified rather than just wired up. Testing it is how I caught F5: one wrong account ID that was silently dropping every log before it reached the alarms.

Every finding fixed in code, so the before/after reads as a Terraform diff. Once the fixes are in, both attacks stop at their first step.

**Where this fits:** Cloud Security Engineer, Application Security, Detection Engineering, DevSecOps.

> Educational lab. The `vulnerable/` code contains intentional misconfigurations, for study only. It is not meant to run in production or on the public internet, and every account ID, key, ARN, and endpoint in the code and docs is a sanitized placeholder.

---

## Table of contents

- [Background & motivation](#background--motivation)
- [Architecture](#architecture)
- [The two attack paths](#the-two-attack-paths)
- [Findings & remediation summary](#findings--remediation-summary)
- [Results](#results)
- [What I learned](#what-i-learned)
- [Repository layout](#repository-layout)
- [Tech stack](#tech-stack)
- [Documentation](#documentation)

---

## Background & motivation

I wanted to understand cloud attacks the way they actually happen. Not isolated bugs from a checklist, but chains, where a few small and very ordinary misconfigurations line up into a full breach. Reading about XXE or a leaked key is one thing. Proving how one leaked commit becomes a production takeover, step by step, is what made the risk concrete for me.

So I did the research before writing any code. Instead of inventing arbitrary bugs, I designed the architecture around the misconfigurations that show up most often, and most damagingly, in real cloud incidents, and mapped each one to a MITRE ATT&CK technique. Then I shaped the environment so those techniques chain the way an attacker would actually use them: application entry point, credential theft, lateral movement, data access, and finally persistence.

| MITRE ATT&CK technique | ID | Where it appears |
| --- | --- | --- |
| Exploit Public-Facing Application | T1190 | Malicious XML upload endpoint (Path 1) |
| Unsecured Credentials: Cloud Instance Metadata API | T1552.005 | SSRF to the ECS task-credential endpoint (Path 1) |
| Data from Cloud Storage | T1530 | Cross-tenant S3 read with stolen credentials (Path 1) |
| Unsecured Credentials: Credentials In Files | T1552.001 | Hardcoded IAM keys in Git history (Path 2) |
| Valid Accounts: Cloud Accounts | T1078.004 | Assuming the over-trusting Deploy Role (Path 2) |
| Supply Chain Compromise | T1195.002 | Backdoored image pushed through the pipeline (Path 2) |
| Implant Internal Image | T1525 | Malicious container image in ECR (Path 2) |

The mapping runs through the whole project. Every intentional weakness reflects a technique defenders see in the wild, and every fix is written to close the technique, not just paper over the one symptom I demonstrated.

## Architecture

A Flask API on **ECS Fargate** behind an **ALB** ingests XML/SVG uploads from tenants A/B/C. Each request is authenticated with a per-tenant API key from **Secrets Manager**; files are stored in **S3** under a tenant prefix and metadata is written to **RDS PostgreSQL**. **CloudTrail** feeds a cross-account detection pipeline in an isolated **security** account.

Three accounts:

| Account | Role |
| --- | --- |
| **Dev** | CI/CD pipeline identity and developer identities |
| **Prod** | All application infrastructure (ECS, ALB, S3, RDS, Secrets Manager, ECR, VPC, CloudTrail) |
| **Security** | Detection and monitoring — CloudWatch alarms, log archive, Lambda forwarder (isolated, no attack surface) |

![Architecture — multi-account cloud environment](docs/screenshots/architecture-diagram.png)

Full detail: **[docs/architecture.md](docs/architecture.md)**.

## The two attack paths

**Path 1 — Application (XXE → SSRF → cross-tenant data breach).**
A malicious XML upload abuses an XML parser with external-entity resolution enabled to read the container credential URI, then performs SSRF against the ECS task-credential endpoint (`169.254.170.2`) to steal the task role's temporary AWS credentials. Because the role holds `s3:*` on the whole bucket and there is no bucket policy, those credentials give full read/write access to **every** tenant's data. Full walk-through: **[docs/attack-path-1-xxe-ssrf.md](docs/attack-path-1-xxe-ssrf.md)**.

**Path 2 — CI/CD (leaked Git credential → prod takeover).**
A hardcoded IAM access key recovered from Git history is used to assume an over-trusting Deploy Role (no MFA or IP conditions), push a backdoored container image, and read every secret in the prod account through a wildcard `secretsmanager:GetSecretValue`. The stolen tenant API keys then allow persistent impersonation that survives credential rotation. Full walk-through: **[docs/attack-path-2-cicd.md](docs/attack-path-2-cicd.md)**.

## Findings & remediation summary

| ID | Finding | Layer | Path | Remediation |
| --- | --- | --- | --- | --- |
| VULN-1 | XML parser resolves external entities (XXE→SSRF) | Application | 1 | Parser hardened: `resolve_entities=False`, `no_network=True`, `load_dtd=False` |
| VULN-2 | API task role `s3:*` + no cross-tenant isolation | IAM / Storage | 1 | Scoped to `GetObject/PutObject/ListBucket` on tenant prefixes; S3 bucket policy denies cross-prefix access |
| — | Container credential URI written to `/tmp` | Application | 1 | Debug write removed |
| VULN-5 | Verbose error/preview responses leak internals | Application | 1 | Responses genericized; parsed `preview` field removed |
| — | Lab-only routes (`/admin/all-objects`, `/files/<key>`, `/lab/secrets-dump`) | Application | 1 | Removed |
| — | ECS security group open egress (`0.0.0.0/0`, all ports) | Network | 1 | Egress restricted to HTTPS + PostgreSQL-to-RDS only |
| F1/F2 | Hardcoded IAM keys in Git history | CI/CD | 2 | Static keys removed; **OIDC** federation; gitleaks secret-scan workflow added |
| F3 | Deploy Role trust policy has no conditions | IAM | 2 | Trust switched to GitHub OIDC with `sub`/`aud` conditions |
| F4 | Deploy Role `secretsmanager:GetSecretValue` on `*` | IAM | 2 | Wildcard secrets policy deleted; deploy permissions scoped |
| F5 | Detection Lambda rejected cross-account invokes (wrong `SourceAccount`) | Detection | — | Fixed permanently in Terraform (`prod_account_id`) |
| VULN-6 | S3 versioning disabled | Storage | 1 | Versioning enabled; TLS-only bucket policy added |

Added defense-in-depth: AWS WAF on the ALB, and a security-posture baseline (GuardDuty, Security Hub, IAM Access Analyzer). Full detail with code diffs: **[docs/remediation.md](docs/remediation.md)**.

## Results

- Both attack paths **fail at the first step** after remediation (documented in the remediation report).
- The cross-account detection pipeline was verified end-to-end; alarms fire on the attack signatures and stay quiet otherwise.

## What I learned

The biggest lesson was that vulnerabilities compose. Nothing here is alarming on its own: an open egress rule, a broad IAM action, a leftover debug file. The damage comes from how they line up, so threat modeling has to follow paths instead of scoring findings one at a time.

A pipeline that can deploy to production holds production-level privilege, even though it looks like "just CI/CD." Securing it with OIDC and scoped trust mattered as much as securing the app.

Detection has to be tested, not just built. My cross-account pipeline looked correct but dropped every event because of one wrong account ID (F5). "Did the alarm actually fire?" is now a step I don't skip.

Least privilege turned out to be very concrete. Swapping `s3:*` for prefix-scoped actions and deleting a wildcard secrets permission were tiny diffs with large impact, and Access Analyzer flags exactly those the moment you enable it.

And because every fix lives in Terraform, the secure version is reproducible and the before/after is a diff someone can read, not a manual change they have to take on trust.

## Repository layout

```
.
├── README.md
├── docs/
│   ├── architecture.md
│   ├── attack-path-1-xxe-ssrf.md
│   ├── attack-path-2-cicd.md
│   ├── remediation.md
│   └── screenshots/            # evidence images
├── infrastructure/
│   ├── vulnerable/             # Terraform — intentionally misconfigured
│   └── hardened/               # Terraform — Phase 2 remediated
├── application/
│   ├── vulnerable/             # Flask API — intentionally vulnerable
│   └── hardened/               # Flask API — remediated
└── .github/workflows/          # secured OIDC deploy + gitleaks secret scan
```

## Tech stack

**AWS:** ECS Fargate, ALB, VPC, S3, RDS PostgreSQL, Secrets Manager, ECR, IAM, CloudTrail, CloudWatch, Lambda, GuardDuty, Security Hub, IAM Access Analyzer, WAF.
**IaC & app:** Terraform (modular, multi-account), Python (Flask), Docker.
**CI/CD & security tooling:** GitHub Actions, GitHub OIDC, gitleaks.

## Documentation

- **[Architecture](docs/architecture.md)** — components, accounts, tenant-isolation model, detection design.
- **[Attack Path 1 — XXE to SSRF](docs/attack-path-1-xxe-ssrf.md)** — application-layer credential theft and cross-tenant breach.
- **[Attack Path 2 — CI/CD compromise](docs/attack-path-2-cicd.md)** — leaked Git credential to full prod takeover.
- **[Remediation](docs/remediation.md)** — layer-by-layer hardening with before/after code diffs and validation.
