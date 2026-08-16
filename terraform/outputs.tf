output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "dispatch_service_name" {
  description = "Name of the dispatch service"
  value       = aws_ecs_service.dispatch.name
}

output "triage_service_name" {
  description = "Name of the triage service"
  value       = aws_ecs_service.triage.name
}

output "dispatch_target_group_arn" {
  description = "ARN of the dispatch target group"
  value       = aws_lb_target_group.dispatch.arn
}

output "triage_target_group_arn" {
  description = "ARN of the triage target group"
  value       = aws_lb_target_group.triage.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "dispatch_log_group" {
  description = "CloudWatch log group for dispatch service"
  value       = aws_cloudwatch_log_group.dispatch.name
}

output "triage_log_group" {
  description = "CloudWatch log group for triage service"
  value       = aws_cloudwatch_log_group.triage.name
}

output "application_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "dispatch_endpoint" {
  description = "Endpoint for dispatch service"
  value       = "http://${aws_lb.main.dns_name}/dispatch"
}

output "triage_endpoint" {
  description = "Endpoint for triage service"
  value       = "http://${aws_lb.main.dns_name}/triage"
}
