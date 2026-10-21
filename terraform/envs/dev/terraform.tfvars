# Dev: cheapest settings that still show a production-style design.
environment              = "dev"
vpc_cidr                 = "10.0.0.0/16"
single_nat_gateway       = true
desired_count            = 1
max_count                = 3
db_multi_az              = false
db_backup_retention_days = 1
deletion_protection      = false
