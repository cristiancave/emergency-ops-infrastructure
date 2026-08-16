variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "emergency-ops"
}

# VPC Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones"
  type        = number
  default     = 2
}

# ECS Variables
variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "emergency-ops-cluster"
}

# Dispatch Service Variables
variable "dispatch_container_port" {
  description = "Dispatch service container port"
  type        = number
  default     = 8080
}

variable "dispatch_cpu" {
  description = "CPU units for dispatch task (256, 512, 1024, 2048, etc.)"
  type        = number
  default     = 256
}

variable "dispatch_memory" {
  description = "Memory in MB for dispatch task"
  type        = number
  default     = 512
}

variable "dispatch_desired_count" {
  description = "Number of dispatch tasks to run"
  type        = number
  default     = 2
}

variable "dispatch_image_uri" {
  description = "Docker image URI for dispatch service"
  type        = string
  default     = "dispatch-service:latest" # Será reemplazado con ECR URI
}

# Triage Service Variables
variable "triage_container_port" {
  description = "Triage service container port"
  type        = number
  default     = 8081
}

variable "triage_cpu" {
  description = "CPU units for triage task"
  type        = number
  default     = 256
}

variable "triage_memory" {
  description = "Memory in MB for triage task"
  type        = number
  default     = 512
}

variable "triage_desired_count" {
  description = "Number of triage tasks to run"
  type        = number
  default     = 2
}

variable "triage_image_uri" {
  description = "Docker image URI for triage service"
  type        = string
  default     = "triage-service:latest" # Será reemplazado con ECR URI
}

variable "triage_db_instance_class" {
  description = "RDS instance class for triage's PostgreSQL database"
  type        = string
  default     = "db.t4g.micro"
}

# OTel Collector Variables
variable "otel_collector_cpu" {
  description = "CPU units for the OTel Collector task"
  type        = number
  default     = 256
}

variable "otel_collector_memory" {
  description = "Memory in MB for the OTel Collector task"
  type        = number
  default     = 512
}

# Auto-scaling Variables
variable "enable_autoscaling" {
  description = "Enable auto-scaling for services"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 4
}

variable "cpu_target" {
  description = "Target CPU utilization for autoscaling"
  type        = number
  default     = 70
}

variable "memory_target" {
  description = "Target memory utilization for autoscaling"
  type        = number
  default     = 80
}
