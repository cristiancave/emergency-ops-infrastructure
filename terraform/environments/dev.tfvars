aws_region         = "us-east-1"
environment        = "dev"
project_name       = "emergency-ops"
availability_zones = 2

# VPC
vpc_cidr = "10.0.0.0/16"

# Dispatch Service
dispatch_cpu            = 256
dispatch_memory         = 512
dispatch_desired_count  = 1
dispatch_container_port = 8080
dispatch_image_uri      = "149511939303.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-dispatch:latest"

# Triage Service
triage_cpu            = 256
triage_memory         = 512
triage_desired_count  = 1
triage_container_port = 8081
triage_image_uri      = "149511939303.dkr.ecr.us-east-1.amazonaws.com/emergency-ops-triage:latest"

# Auto-scaling
enable_autoscaling = false
min_capacity       = 1
max_capacity       = 2
cpu_target         = 70
memory_target      = 80
