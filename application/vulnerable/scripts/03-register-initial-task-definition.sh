#!/usr/bin/env bash
# 03-register-initial-task-definition.sh
# -----------------------------------------------------------------------------
# Registers the FIRST revision of sec-lab-task-prod in the prod account so the
# sec-lab-service-prod ECS service has something to start from before the
# first GitHub Actions run. Subsequent deploys are handled by the pipeline.
#
# Run from a shell that has credentials for the prod account (either the
# Deploy Role assumed manually, or Break-glass Admin for the initial setup).
#
# Usage:
#   export AWS_PROFILE=sec-lab-prod
#   export PROD_ACCOUNT_ID=111111111111
#   export S3_BUCKET_SUFFIX=abc123
#   export RDS_ENDPOINT=sec-lab-db-prod.XXXXXXXXXXXX.eu-west-3.rds.amazonaws.com
#   ./scripts/03-register-initial-task-definition.sh
# -----------------------------------------------------------------------------

set -euo pipefail

: "${PROD_ACCOUNT_ID:?PROD_ACCOUNT_ID env var is required}"
: "${S3_BUCKET_SUFFIX:?S3_BUCKET_SUFFIX env var is required (random suffix on the sec-lab-data-prod bucket)}"
: "${RDS_ENDPOINT:?RDS_ENDPOINT env var is required (full RDS hostname)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

RENDERED="/tmp/sec-lab-task-prod.json"

echo "[*] Rendering task-definition.json"
sed \
  -e "s/111111111111/${PROD_ACCOUNT_ID}/g" \
  -e "s/sec-lab-data-prod-REPLACEME/sec-lab-data-prod-${S3_BUCKET_SUFFIX}/g" \
  -e "s|sec-lab-db-prod.REPLACEME.eu-west-3.rds.amazonaws.com|${RDS_ENDPOINT}|g" \
  task-definition.json > "${RENDERED}"

echo "[*] Registering task definition revision"
REVISION_ARN="$(aws ecs register-task-definition \
  --cli-input-json "file://${RENDERED}" \
  --region eu-west-3 \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)"

echo
echo "[+] Registered: ${REVISION_ARN}"
echo
echo "If this is the very first revision, update sec-lab-service-prod to use it:"
echo "  aws ecs update-service \\"
echo "    --cluster sec-lab-cluster-prod \\"
echo "    --service sec-lab-service-prod \\"
echo "    --task-definition ${REVISION_ARN} \\"
echo "    --region eu-west-3"
