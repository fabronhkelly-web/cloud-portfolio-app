# GuardDuty, AWS Config and Security Hub with the NIST 800-53 Rev. 5 standard
# (NIST CA-7 continuous monitoring, SI-4 system monitoring, CM-8 component inventory)

# ---------- GuardDuty: the guard watching the cameras ----------
resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:Single AWS account with no AWS Organization
  enable = true
}

# ---------- AWS Config: the inventory clipboard ----------
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

resource "aws_s3_bucket" "config" {
  #checkov:skip=CKV_AWS_144:Cross-region replication is not needed for a single-region portfolio project
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is used; a customer-managed KMS key is a planned improvement
  #checkov:skip=CKV_AWS_18:Access logging for the log bucket itself is out of scope
  #checkov:skip=CKV2_AWS_62:No event notifications needed for the log bucket
  bucket        = "portfolio-config-${local.account_id}"
  force_destroy = true # lets terraform destroy remove it for this demo
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    id     = "expire-old-snapshots"
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

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid       = "AllowConfigBucketCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
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

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_service_linked_role.config.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# ---------- Security Hub: the inspector with the report card ----------
resource "aws_securityhub_account" "main" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
  depends_on                = [aws_config_configuration_recorder_status.main]
}

resource "aws_securityhub_standards_subscription" "nist_800_53" {
  standards_arn = "arn:aws:securityhub:${local.region}::standards/nist-800-53/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]
}
