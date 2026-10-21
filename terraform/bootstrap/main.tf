# Bootstrap: one-time, account-level setup that everything else depends on.
#   1. S3 bucket for Terraform remote state (with native S3 locking)
#   2. GitHub OIDC provider + IAM role so GitHub Actions can deploy WITHOUT stored AWS keys
#   3. A monthly AWS Budget alert
# This folder uses local state on purpose (it creates the bucket the others store state in).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "cloud-portfolio-app"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# 1. Remote state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  #checkov:skip=CKV_AWS_144:Cross-region replication is not needed for a single-region portfolio project
  #checkov:skip=CKV_AWS_18:Access logging for the state bucket is out of scope (CloudTrail records API access)
  #checkov:skip=CKV2_AWS_62:No event notifications needed for the state bucket
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is sufficient; a customer-managed KMS key adds cost
  bucket = "portfolio-tfstate-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # lets us recover an older state file if something goes wrong
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Refuse any request that isn't over HTTPS.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# ---------------------------------------------------------------------------
# 2. GitHub Actions -> AWS via OIDC (no long-lived access keys anywhere)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only workflows in THIS repository can assume the role.
    # GitHub now puts immutable owner/repo IDs in the subject ("repo:owner@123/name@456:ref:...").
    # Matching on the IDs means a different repo that later takes the same name can't get in.
    # The name-only pattern is kept for accounts still using the older subject format.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = compact([
        var.github_repo_id_subject == "" ? "" : "repo:${var.github_repo_id_subject}:*",
        "repo:${var.github_repo}:*",
      ])
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "portfolio-github-actions"
  description          = "Assumed by GitHub Actions in ${var.github_repo} via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Broad service access (no IAM) ...
resource "aws_iam_role_policy_attachment" "github_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ... plus IAM access limited to roles whose names start with "portfolio-".
# The pipeline can create the app's own roles, but cannot touch any other role in the account.
data "aws_iam_policy_document" "github_scoped_iam" {
  statement {
    sid = "ManageProjectRolesOnly"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/portfolio-*"]
  }
  statement {
    sid       = "PassProjectRolesToServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/portfolio-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_scoped_iam" {
  name   = "scoped-iam"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_scoped_iam.json
}

# ---------------------------------------------------------------------------
# 3. Monthly budget alert
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  count        = var.alert_email == "" ? 0 : 1
  name         = "portfolio-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
