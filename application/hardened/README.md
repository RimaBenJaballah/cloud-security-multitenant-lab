# Cloud Security Lab — Phase 2 Secured Application

This repository is the secured Phase 2 version of the multi-tenant data ingestion API.
It keeps the same application role as Phase 1, but removes the intentional weaknesses used in the two attack paths.

## Main security changes

- Safe XML/SVG parsing: DTD loading, external entities, and parser network access are disabled.
- Removed `/tmp/cred_uri` debug file creation.
- Removed sensitive `preview` content from API responses.
- Sanitized error responses; full details are logged server-side only.
- Removed lab-only vulnerable routes:
  - `/admin/all-objects`
  - `/files/<s3_key>`
  - `/lab/secrets-dump`
- Tenant API key cache now uses a short TTL.
- GitHub Actions deploys with OIDC, not static AWS access keys.
- Docker images are deployed with immutable Git commit SHA tags.
- A Gitleaks workflow scans for accidental secrets.

## Required AWS side

Before pushing this app to `main`, deploy the Phase 2 Terraform and set:

```hcl
github_repository = "<your-github-username>/cloud-security-multitenant-lab"
github_branch     = "main"
```

The workflow assumes this role:

```text
arn:aws:iam::111111111111:role/sec-lab-deploy-role-prod
```

## Local run

```bash
docker compose up --build
```

Health check:

```bash
curl http://localhost:8080/health
```

Upload test file locally:

```bash
curl -X POST "http://localhost:8080/upload" \
  -H "X-API-Key: lab-key-tenant-a" \
  -F "file=@test.xml"
```
