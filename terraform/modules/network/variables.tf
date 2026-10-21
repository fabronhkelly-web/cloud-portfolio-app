variable "name" {
  description = "Name prefix for all resources, e.g. portfolio-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheaper); false = one per AZ (more resilient)"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "How long to keep VPC flow logs"
  type        = number
  default     = 14
}
