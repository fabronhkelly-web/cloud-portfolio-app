terraform {
  backend "s3" {
    bucket       = "portfolio-tfstate-115122815971"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # native S3 state locking (Terraform 1.10+), no DynamoDB table needed
    encrypt      = true
  }
}
