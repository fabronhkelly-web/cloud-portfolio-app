variable "name" {
  description = "Repository name"
  type        = string
}

variable "keep_images" {
  type    = number
  default = 10
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository even if it still has images"
  type        = bool
  default     = true
}
