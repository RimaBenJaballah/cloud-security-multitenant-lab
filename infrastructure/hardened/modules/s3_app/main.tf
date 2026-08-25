###############################################################################
# S3 Bucket — tenant data
# Hardened: versioning, public access block, TLS-only policy, known-prefix guard.
###############################################################################

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket        = "sec-lab-data-prod-${random_id.suffix.hex}"
  force_destroy = true

  tags = { Name = "sec-lab-data-prod" }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyObjectActionsOutsideKnownTenantPrefixes"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        NotResource = [
          "${aws_s3_bucket.this.arn}/tenant-a/*",
          "${aws_s3_bucket.this.arn}/tenant-b/*",
          "${aws_s3_bucket.this.arn}/tenant-c/*"
        ]
      }
    ]
  })
}
