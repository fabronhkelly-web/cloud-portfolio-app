# Private container registry for the app image.

resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_51:Mutable tags allow a moving "latest" tag for the first deploy; the pipeline deploys immutable commit-SHA tags
  #checkov:skip=CKV_AWS_136:AES256 encryption is used; a customer-managed KMS key adds cost
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true # AWS scans every pushed image for known vulnerabilities
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep only the newest images so storage costs stay near zero.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last ${var.keep_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_images
      }
      action = { type = "expire" }
    }]
  })
}
