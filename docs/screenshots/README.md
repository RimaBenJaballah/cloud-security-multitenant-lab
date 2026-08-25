# Screenshots

Drop your evidence images here using the **exact filenames** below — the docs already reference them, so they render automatically once the files exist.

Recommended: PNG, readable width (~1200px+), and **redact** any real account IDs, access keys, ARNs, endpoints, or credential values before saving (mask keys like `AKIA****`, blur session tokens and passwords).

Aim for three kinds of evidence, not just the attacks: proof you **built** the environment, proof you **broke** it, and proof you **detected and fixed** it. The infrastructure shots are what tell a reader the environment is real and not just theory.

**Build the environment (proof it's real)**

| Filename | Shows |
| --- | --- |
| `infra-terraform-apply.png` | A `terraform apply` completing (resources created) |
| `infra-ecs-service-running.png` | ECS console: the service healthy with a running task |
| `infra-alb-health.png` | `curl /health` returning 200 through the ALB, or the target group healthy |
| `infra-s3-tenant-prefixes.png` | S3 bucket showing the `tenant-a/ tenant-b/ tenant-c/` prefixes |
| `infra-accounts-org.png` | The three accounts (Organizations view or three console logins) |

**Attacks and detection**

| Filename | Shows |
| --- | --- |
| `architecture-diagram.png` | The multi-account architecture (accounts, ALB→ECS→S3/RDS, detection pipeline) |
| `attack1-stage1-cred-uri.png` | Path 1 — XXE file read returning the `/tmp/cred_uri` path in the `preview` field |
| `attack1-stage2-credential-theft.png` | Path 1 — SSRF returning the task-role temporary credentials |
| `attack1-stage3-cross-tenant-s3.png` | Path 1 — `aws s3 ls` listing all tenant prefixes with stolen creds |
| `attack1-detection-alarm.png` | Path 1 — CloudWatch alarm / metric filter firing on direct S3 access |
| `attack2-phase1-gitleaks.png` | Path 2 — gitleaks recovering the leaked AWS key from Git history |
| `attack2-phase2-assumerole.png` | Path 2 — `get-caller-identity` showing the cross-account Deploy Role assumption |
| `attack2-phase3-deploy.png` | Path 2 — ECS rolling deployment of the backdoored image completing |
| `attack2-phase3-webhook-exfil.png` | Path 2 — webhook dashboard receiving env + task-role creds (redacted) |
| `attack2-phase4-secrets-dump.png` | Path 2 — all four secrets dumped via the Deploy Role |
| `attack2-phase4-tenant-impersonation.png` | Path 2 — successful upload as tenant C from a shell with no AWS creds |
| `attack2-phase5-alarms.png` | Path 2 — both Path 2 alarms in `ALARM` state |
| `securityhub-before.png` | Security Hub compliance score before remediation |
| `securityhub-after.png` | Security Hub compliance score after remediation |
| `remediation-path1-blocked.png` | Path 1 re-run failing after remediation |
| `remediation-path2-blocked.png` | Path 2 re-run failing after remediation |

You can add more images than this list; just reference them in the relevant doc with `![caption](screenshots/your-file.png)`.
