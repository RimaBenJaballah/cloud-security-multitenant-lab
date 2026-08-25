#!/usr/bin/env bash
set -euo pipefail

USER_NAME="sec-lab-pipeline-user-dev"
POLICY_NAME="sec-lab-pipeline-user-assume-deploy-role"
POLICY_FILE="iam/pipeline-user-policy.json"

: "${PROD_ACCOUNT_ID:?PROD_ACCOUNT_ID env var is required (the prod AWS account id)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

TMP_DIR=".tmp"
mkdir -p "${TMP_DIR}"
RENDERED_POLICY_FILE="${TMP_DIR}/${POLICY_NAME}.json"

echo "[*] Rendering policy with PROD_ACCOUNT_ID=${PROD_ACCOUNT_ID}"
sed "s/PROD_ACCOUNT_ID/${PROD_ACCOUNT_ID}/g" "${POLICY_FILE}" > "${RENDERED_POLICY_FILE}"

echo "[*] Creating IAM user: ${USER_NAME}"
if aws iam get-user --user-name "${USER_NAME}" >/dev/null 2>&1; then
  echo "    user already exists, skipping create"
else
  aws iam create-user --user-name "${USER_NAME}" \
    --tags "Key=project,Value=sec-lab" "Key=purpose,Value=cicd-pipeline"
fi

DEV_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "[*] Creating managed policy: ${POLICY_NAME}"
if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "    policy already exists, creating new default version"
  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document "file://./${RENDERED_POLICY_FILE}" \
    --set-as-default >/dev/null
else
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document "file://./${RENDERED_POLICY_FILE}" >/dev/null
fi

echo "[*] Attaching policy to user"
aws iam attach-user-policy \
  --user-name "${USER_NAME}" \
  --policy-arn "${POLICY_ARN}"

echo "[*] Checking existing access keys"
EXISTING_KEY_COUNT="$(aws iam list-access-keys \
  --user-name "${USER_NAME}" \
  --query 'length(AccessKeyMetadata)' \
  --output text)"

if [[ "${EXISTING_KEY_COUNT}" -ge 2 ]]; then
  echo "[!] This IAM user already has 2 access keys."
  echo "    AWS does not allow more than 2 keys per IAM user."
  echo "    Run this to list them:"
  echo "    aws iam list-access-keys --user-name ${USER_NAME}"
  echo "    Then delete one old key if needed."
  exit 1
fi

echo "[*] Generating access key pair"
KEY_OUTPUT="$(aws iam create-access-key \
  --user-name "${USER_NAME}" \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' \
  --output text)"

ACCESS_KEY_ID="$(echo "${KEY_OUTPUT}" | awk '{print $1}')"
SECRET_ACCESS_KEY="$(echo "${KEY_OUTPUT}" | awk '{print $2}')"

cat <<EOT

-----------------------------------------------------------------------------
 DEV ACCOUNT IAM USER READY
-----------------------------------------------------------------------------
 User name : ${USER_NAME}
 User ARN  : arn:aws:iam::${DEV_ACCOUNT_ID}:user/${USER_NAME}
 Policy    : ${POLICY_ARN}

 AWS_ACCESS_KEY_ID     = ${ACCESS_KEY_ID}
 AWS_SECRET_ACCESS_KEY = ${SECRET_ACCESS_KEY}

 Paste these two values into .github/workflows/deploy.yml.

-----------------------------------------------------------------------------
EOT
