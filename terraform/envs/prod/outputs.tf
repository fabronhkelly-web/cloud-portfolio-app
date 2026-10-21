output "app_url" {
  description = "Open this in a browser"
  value       = "http://${module.compute.alb_dns_name}"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster" {
  value = module.compute.cluster_name
}

output "ecs_service" {
  value = module.compute.service_name
}

output "db_endpoint" {
  value = "${module.database.address}:${module.database.port}"
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${module.monitoring.dashboard_name}"
}
