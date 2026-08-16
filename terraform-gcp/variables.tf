variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "project-7357d751-3d80-40cf-858"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Ambiente (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "collector_cpu" {
  description = "CPU asignada al contenedor del Collector (Cloud Run)"
  type        = string
  default     = "1"
}

variable "collector_memory" {
  description = "Memoria asignada al contenedor del Collector (Cloud Run)"
  type        = string
  default     = "512Mi"
}
