output "state_bucket" {
  description = "S3 bucket that stores Terraform state for dev and prod"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  description = "Put this in the GitHub repo variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
