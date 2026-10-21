# Prod: same modules as dev, sized for resilience. Planned in CI on every change;
# applied only when you want to demo it (it costs more to run).
environment              = "prod"
vpc_cidr                 = "10.1.0.0/16"
single_nat_gateway       = false
desired_count            = 2
max_count                = 6
db_multi_az              = true
db_backup_retention_days = 7
deletion_protection      = true
