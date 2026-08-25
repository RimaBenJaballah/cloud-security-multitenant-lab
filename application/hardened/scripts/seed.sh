#!/bin/sh
set -e

ENDPOINT="http://localstack:4566"

echo ">>> Creating S3 bucket..."
aws --endpoint-url=$ENDPOINT s3 mb s3://sec-lab-data-prod-local 2>/dev/null || true

echo ">>> Seeding tenant API keys in Secrets Manager..."

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "tenant-a/api-key" \
  --secret-string "lab-key-tenant-a" 2>/dev/null || \
aws --endpoint-url=$ENDPOINT secretsmanager update-secret \
  --secret-id "tenant-a/api-key" \
  --secret-string "lab-key-tenant-a"

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "tenant-b/api-key" \
  --secret-string "lab-key-tenant-b" 2>/dev/null || \
aws --endpoint-url=$ENDPOINT secretsmanager update-secret \
  --secret-id "tenant-b/api-key" \
  --secret-string "lab-key-tenant-b"

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "tenant-c/api-key" \
  --secret-string "lab-key-tenant-c" 2>/dev/null || \
aws --endpoint-url=$ENDPOINT secretsmanager update-secret \
  --secret-id "tenant-c/api-key" \
  --secret-string "lab-key-tenant-c"

aws --endpoint-url=$ENDPOINT secretsmanager create-secret \
  --name "rds/credentials" \
  --secret-string '{"username":"dbadmin","password":"labpassword123"}' 2>/dev/null || true

echo ">>> Uploading sample tenant files to S3..."

echo '<data version="1.0"><record>seed</record></data>' > /tmp/sample_a.xml
echo '<data version="2.1"><record>r1</record><record>r2</record></data>' > /tmp/sample_b.xml
echo '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"></svg>' > /tmp/sample_c.svg

aws --endpoint-url=$ENDPOINT s3 cp /tmp/sample_a.xml s3://sec-lab-data-prod-local/tenant-a/sample_data.xml
aws --endpoint-url=$ENDPOINT s3 cp /tmp/sample_b.xml s3://sec-lab-data-prod-local/tenant-b/report_q1.xml
aws --endpoint-url=$ENDPOINT s3 cp /tmp/sample_c.svg  s3://sec-lab-data-prod-local/tenant-c/inventory.svg

echo ">>> LocalStack seed complete."
