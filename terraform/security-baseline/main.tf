# Security baseline: account-wide security services for the DoD-ready upgrade.
#   CloudTrail (audit trail), GuardDuty, AWS Config, Security Hub (NIST 800-53),
#   and an automatic fix for SSH open to the internet.
# Applied from your own computer with SSO, not by the pipeline.
# The pipeline's Checkov and fmt checks still scan every file here.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "portfolio-tfstate-115122815971"
    key          = "security-baseline/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "cloud-portfolio-app"
      ManagedBy = "terraform"
      Stack     = "security-baseline"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
