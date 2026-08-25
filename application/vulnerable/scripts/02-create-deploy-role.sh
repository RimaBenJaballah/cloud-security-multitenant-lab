#!/usr/bin/env bash
# 02-create-deploy-role.sh
# -----------------------------------------------------------------------------
# Runs against the PROD account. Creates:
#   - IAM role   : sec-lab-deploy-role-prod
#                  Trust policy principal: arn:aws:iam::<DEV>:user/sec-lab-pipeline-user-dev
#                  NO conditions (no MFA, no IP)  <-- Path 2 misconfig
#   - IAM policy : sec-lab-deploy-role-permissions-prod
#                  ECR push + ECS deploy + iam:PassRole on the two task roles +
#                  secretsmanager:GetSecretValue on *  <-- Path 2 exfil misconfig
#
# Prereqs:
#   - AWS CLI configured with a profile that has IAM admin in the PROD account.
#   - DEV_ACCOUNT_ID env var set (the account where the pipeline IAM user lives).
#
# Usage:
#   export AWS_PROFILE=sec-lab-prod
#   export DEV_ACCOUNT_ID=222222222222
#   ./scripts/02-create-deploy-role.sh
# -----------------------------------------------------------------------------

set -euo pipefail

ROLE_NAME="sec-lab-deploy-role-prod"
POLICY_NAME="sec-lab-deploy-role-permissions-prod"
TRUST_FILE="iam/deploy-role-trust-policy.json"
PERMS_FILE="iam/deploy-role-permissions-policy.json"

RENDERED_TRUST="/tmp/${ROLE_NAME}-trust.json"
RENDERED_PERMS="/tmp/${POLICY_NAME}.json"

: "${DEV_ACCOUNT_ID:?DEV_ACCOUNT_ID env var is required (the dev AWS account id)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PROD_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "[*] Rendering trust policy (dev account ${DEV_ACCOUNT_ID} -> prod role)"
sed "s/DEV_ACCOUNT_ID/${DEV_ACCOUNT_ID}/g" "${TRUST_FILE}" > "${RENDERED_TRUST}"

echo "[*] Rendering permissions policy (prod account ${PROD_ACCOUNT_ID})"
sed "s/PROD_ACCOUNT_ID/${PROD_ACCOUNT_ID}/g" "${PERMS_FILE}" > "${RENDERED_PERMS}"

echo "[*] Creating role: ${ROLE_NAME}"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "    role already exists, updating trust policy"
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "file://${RENDERED_TRUST}"
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${RENDERED_TRUST}" \
    --description "CI/CD deploy role assumed cross-account by sec-lab-pipeline-user-dev. INTENTIONALLY has no MFA/IP conditions (Path 2 misconfig)." \
    --max-session-duration 3600 \
    --tags "Key=project,Value=sec-lab" "Key=purpose,Value=cicd-deploy" >/dev/null
fi

POLICY_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "[*] Creating/updating managed policy: ${POLICY_NAME}"
if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "    policy already exists, creating new default version"
  # Clean up old non-default versions if we've hit the 5-version cap.
  VERSIONS_JSON="$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}")"
  NON_DEFAULT_OLDEST="$(echo "${VERSIONS_JSON}" | python3 -c '
import json,sys
data=json.load(sys.stdin)["Versions"]
nd=[v for v in data if not v["IsDefaultVersion"]]
nd.sort(key=lambda v:v["CreateDate"])
print(nd[0]["VersionId"] if len(data)>=5 and nd else "")
')"
  if [[ -n "${NON_DEFAULT_OLDEST}" ]]; then
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${NON_DEFAULT_OLDEST}"
  fi
  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document "file://${RENDERED_PERMS}" \
    --set-as-default >/dev/null
else
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://${RENDERED_PERMS}" \
    --description "Intended ECR push + ECS deploy + iam:PassRole + additive misconfig: secretsmanager:GetSecretValue on *" >/dev/null
fi

echo "[*] Attaching policy to role"
aws iam attach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn "${POLICY_ARN}"

cat <<EOF

-----------------------------------------------------------------------------
 PROD ACCOUNT DEPLOY ROLE CREATED
-----------------------------------------------------------------------------
 Role name : ${ROLE_NAME}
 Role ARN  : arn:aws:iam::${PROD_ACCOUNT_ID}:role/${ROLE_NAME}
 Policy    : ${POLICY_ARN}

 Trust policy: principal is arn:aws:iam::${DEV_ACCOUNT_ID}:user/sec-lab-pipeline-user-dev
   -> NO MFA condition, NO IP condition (intentional Path 2 misconfig)

 Permissions:
   - ECR push scoped to sec-lab-api repo
   - ECS deploy (RegisterTaskDefinition / UpdateService / etc)
   - iam:PassRole on sec-lab-task-role-prod + sec-lab-execution-role-prod
   - secretsmanager:GetSecretValue on *  (INTENTIONAL Path 2 over-permission)

 Next: update .github/workflows/deploy.yml so DEPLOY_ROLE_ARN and
 PROD_ACCOUNT_ID match the values above, then push to main to trigger deploy.
-----------------------------------------------------------------------------
EOF
