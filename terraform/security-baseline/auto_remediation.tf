# Automatic fix: close SSH that is open to the whole internet (NIST SC-7, CM-6, AC-6)

# The rule: flag any security group that allows SSH from anywhere
resource "aws_config_config_rule" "restricted_ssh" {
  name = "portfolio-restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

# Who the fix-it script runs as: Systems Manager, only in this account
data "aws_iam_policy_document" "remediation_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "remediation" {
  name               = "portfolio-config-remediation"
  description        = "Lets AWS Config remove SSH rules that are open to the internet"
  assume_role_policy = data.aws_iam_policy_document.remediation_assume.json
}

# What it may do: read security groups, and remove rules from them. Nothing else.
data "aws_iam_policy_document" "remediation_permissions" {
  statement {
    sid       = "ReadSecurityGroups"
    actions   = ["ec2:DescribeSecurityGroups"]
    resources = ["*"] # Describe actions cannot be limited to specific resources
  }
  statement {
    sid       = "RemoveBadRules"
    actions   = ["ec2:RevokeSecurityGroupIngress"]
    resources = ["arn:aws:ec2:${local.region}:${local.account_id}:security-group/*"]
  }
}

resource "aws_iam_role_policy" "remediation" {
  name   = "revoke-open-ssh"
  role   = aws_iam_role.remediation.id
  policy = data.aws_iam_policy_document.remediation_permissions.json
}

# The automatic fix: when the rule flags a security group, run the AWS script on it
resource "aws_config_remediation_configuration" "restricted_ssh" {
  config_rule_name           = aws_config_config_rule.restricted_ssh.name
  target_type                = "SSM_DOCUMENT"
  target_id                  = "AWS-DisableIncomingSSHOnPort22"
  automatic                  = true
  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.remediation.arn
  }
  parameter {
    name           = "SecurityGroupIds"
    resource_value = "RESOURCE_ID"
  }
}
