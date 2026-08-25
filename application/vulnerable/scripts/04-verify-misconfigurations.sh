#!/usr/bin/env bash
# 04-verify-misconfigurations.sh
# -----------------------------------------------------------------------------
# Sanity-checks that the Path 2 misconfigurations are ACTUALLY present after
# running scripts 01 and 02. Useful after you wire everything up to confirm
# the lab is exploitable as intended.
#
# Checks:
#   [A] Deploy Role trust policy has no Condition block (no MFA, no IP).
#   [B] Deploy Role permissions include secretsmanager:GetSecretValue on "*".
#   [C] Pipeline user has ONLY the AssumeRole policy (not admin).
#   [D] Hardcoded creds are present in .github/workflows/deploy.yml.
#
# Run from the prod account profile (for A + B) and dev account profile (for C).
# -----------------------------------------------------------------------------

set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "=== [D] Checking for hardcoded credentials in workflow ==="
WORKFLOW=".github/workflows/deploy.yml"
if grep -E '^\s*AWS_ACCESS_KEY_ID:\s*"AKIA' "${WORKFLOW}" >/dev/null 2>&1; then
  pass "Hardcoded AWS_ACCESS_KEY_ID present in ${WORKFLOW} (Path 2 misconfig intact)"
else
  warn "No AKIA-style access key literal in ${WORKFLOW} — did you paste the keys printed by script 01?"
fi

if [[ "${SKIP_AWS_CHECKS:-0}" = "1" ]]; then
  echo
  warn "SKIP_AWS_CHECKS=1 set, skipping AWS API checks."
  exit 0
fi

echo
echo "=== [A] Deploy Role trust policy has no Condition ==="
TRUST_JSON="$(aws iam get-role --role-name sec-lab-deploy-role-prod --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || true)"
if [[ -z "${TRUST_JSON}" ]]; then
  fail "Could not fetch sec-lab-deploy-role-prod — are you authenticated to the prod account?"
else
  HAS_CONDITION="$(echo "${TRUST_JSON}" | python3 -c '
import json,sys
doc=json.load(sys.stdin)
for s in doc.get("Statement",[]):
    if "Condition" in s:
        print("yes"); sys.exit(0)
print("no")
')"
  if [[ "${HAS_CONDITION}" = "no" ]]; then
    pass "Trust policy has no Condition block (Path 2 misconfig intact)"
  else
    fail "Trust policy has a Condition block — the MFA/IP vuln has been removed"
  fi
fi

echo
echo "=== [B] Deploy Role has secretsmanager:GetSecretValue on * ==="
POLICY_ARN="$(aws iam list-attached-role-policies --role-name sec-lab-deploy-role-prod \
  --query "AttachedPolicies[?PolicyName=='sec-lab-deploy-role-permissions-prod'].PolicyArn | [0]" --output text 2>/dev/null || true)"
if [[ -z "${POLICY_ARN}" || "${POLICY_ARN}" = "None" ]]; then
  fail "sec-lab-deploy-role-permissions-prod not attached to Deploy Role"
else
  VERSION_ID="$(aws iam get-policy --policy-arn "${POLICY_ARN}" --query 'Policy.DefaultVersionId' --output text)"
  DOC="$(aws iam get-policy-version --policy-arn "${POLICY_ARN}" --version-id "${VERSION_ID}" --query 'PolicyVersion.Document' --output json)"
  HAS_WILDCARD_SECRETS="$(echo "${DOC}" | python3 -c '
import json,sys
doc=json.load(sys.stdin)
for s in doc.get("Statement",[]):
    actions=s.get("Action",[])
    if isinstance(actions,str): actions=[actions]
    resources=s.get("Resource",[])
    if isinstance(resources,str): resources=[resources]
    if s.get("Effect")=="Allow" and "secretsmanager:GetSecretValue" in actions and "*" in resources:
        print("yes"); sys.exit(0)
print("no")
')"
  if [[ "${HAS_WILDCARD_SECRETS}" = "yes" ]]; then
    pass "secretsmanager:GetSecretValue on * present (Path 2 exfil misconfig intact)"
  else
    fail "secretsmanager:GetSecretValue is NOT on * — Path 2 exfil step is blocked"
  fi
fi

echo
echo "=== [C] Pipeline user has only the AssumeRole policy ==="
echo "    (run this against the DEV account profile)"
USER_POLICIES="$(aws iam list-attached-user-policies --user-name sec-lab-pipeline-user-dev \
  --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null || echo "__ERR__")"
if [[ "${USER_POLICIES}" = "__ERR__" ]]; then
  warn "Could not fetch sec-lab-pipeline-user-dev — switch to dev account profile and re-run"
elif [[ "${USER_POLICIES}" = "sec-lab-pipeline-user-assume-deploy-role" ]]; then
  pass "Pipeline user has only the AssumeRole policy (intended)"
else
  fail "Pipeline user has unexpected policies: ${USER_POLICIES}"
fi

echo
echo "Done."
