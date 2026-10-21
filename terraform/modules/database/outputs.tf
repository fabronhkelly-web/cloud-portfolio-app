output "address" {
  description = "Database hostname"
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "secret_arn" {
  description = "Secrets Manager secret holding the username and password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
