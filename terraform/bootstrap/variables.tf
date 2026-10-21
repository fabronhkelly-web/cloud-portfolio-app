variable "region" {
  description = "AWS region for the project"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name"
  type        = string
  default     = "fabronhkelly-web/cloud-portfolio-app"
}

variable "github_repo_id_subject" {
  description = "owner@ownerId/repo@repoId as it appears in GitHub's OIDC subject claim (found in CloudTrail)"
  type        = string
  default     = "fabronhkelly-web@338725228/cloud-portfolio-app@1428726980"
}

variable "alert_email" {
  description = "Email address for budget alerts (set with the TF_VAR_alert_email environment variable)"
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly spend that triggers budget alerts"
  type        = number
  default     = 20
}
