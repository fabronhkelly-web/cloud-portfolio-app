# Managed Postgres in the private subnets. AWS generates the master password and stores it in
# Secrets Manager (manage_master_user_password), so no password ever appears in code or state.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.name}-db" }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_118:Enhanced monitoring adds cost; basic CloudWatch metrics + alarms are used instead
  #checkov:skip=CKV_AWS_353:Performance Insights is not needed at this scale
  #checkov:skip=CKV_AWS_354:Performance Insights is disabled, so no PI KMS key
  #checkov:skip=CKV_AWS_157:Multi-AZ is enabled in prod via var.multi_az; dev stays single-AZ to save cost
  #checkov:skip=CKV_AWS_293:Deletion protection is enabled in prod via var.deletion_protection; dev must be destroyable
  #checkov:skip=CKV2_AWS_30:Query logging is not needed; postgresql logs are exported to CloudWatch
  #checkov:skip=CKV2_AWS_60:Copy-tags-to-snapshot is enabled
  identifier     = "${var.name}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = 20
  max_allocated_storage = 50 # storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true

  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.name}-db-final" : null
  apply_immediately       = true
}
