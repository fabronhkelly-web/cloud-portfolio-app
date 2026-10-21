variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  description = "dev or prod"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "desired_count" {
  type = number
}

variable "max_count" {
  type = number
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

variable "deletion_protection" {
  type = bool
}

variable "alert_email" {
  description = "Where alarm emails go. Set with the TF_VAR_alert_email environment variable (kept out of the public repo)."
  type        = string
  default     = ""
}
