# CloudTrail: an audit trail of every action in the account (NIST AU-2, AU-9, AU-12)

locals {
  trail_name      = "portfolio-trail"
  trail_arn       = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  trail_log_group = "/aws/cloudtrail/${local.trail_name}"
}

# Customer-managed KMS key that encrypts the CloudTrail logs (NIST SC-12, SC-13, SC-28, AU-9)
resource "aws_kms_key" "cloudtrail" {
  description             = "Encrypts CloudTrail log files for portfolio-trail"
  enable_key_rotation     = true # a new key version every year, automatically
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdminsManageTheKey"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudTrailEncryptsLogs"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${local.account_id}:trail/*" }
        }
      },
      {
        Sid       = "CloudTrailDescribesKey"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "kms:DescribeKey"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
        }
      },
      {
        Sid       = "CloudWatchLogsEncryptsTrailLogGroup"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.trail_log_group}" }
        }
      },
      {
        Sid       = "AccountUsersReadLogs"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = ["kms:Decrypt", "kms:ReEncryptFrom"]
        Resource  = "*"
        Condition = {
          StringLike = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${local.account_id}:trail/*" }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/portfolio-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

resource "aws_s3_bucket" "trail" {
  #checkov:skip=CKV_AWS_144:Cross-region replication is not needed for a single-region portfolio project
  #checkov:skip=CKV_AWS_18:Access logging for the log bucket itself is out of scope
  #checkov:skip=CKV2_AWS_62:No event notifications needed for the log bucket
  bucket        = "portfolio-cloudtrail-${local.account_id}"
  force_destroy = true # lets terraform destroy remove it for this demo; a real system would keep it
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true # fewer KMS calls, lower cost
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AllowCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AllowCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_252:SNS notifications for each new log file are not needed
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn

  # Also stream every event to CloudWatch Logs so it can be searched and alarmed on (NIST AU-6, SI-4)
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_to_cloudwatch]
}

# ---------------------------------------------------------------------------
# CloudWatch Logs copy of the trail (fixes Security Hub CloudTrail.5)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "trail" {
  name              = local.trail_log_group
  retention_in_days = 365 # keep audit records one year (NIST AU-11)
  kms_key_id        = aws_kms_key.cloudtrail.arn
}

# CloudTrail needs a role it can assume to write into the log group
resource "aws_iam_role" "trail_to_cloudwatch" {
  name = "portfolio-cloudtrail-to-cloudwatch"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
    }]
  })
}

# Least privilege: it can only create streams and write events in this one log group
resource "aws_iam_role_policy" "trail_to_cloudwatch" {
  name = "write-trail-log-group"
  role = aws_iam_role.trail_to_cloudwatch.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}
