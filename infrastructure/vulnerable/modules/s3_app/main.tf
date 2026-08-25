###############################################################################
# S3 Bucket — tenant data
# MISCONFIGURATION: no tenant isolation via bucket policy, versioning off
###############################################################################

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket        = "sec-lab-data-prod-${random_id.suffix.hex}"
  force_destroy = true

  tags = { Name = "sec-lab-data-prod" }
}

# Versioning intentionally NOT enabled (default off) — allows data tampering
# in Path 1. New buckets have versioning off; no resource needed.

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
