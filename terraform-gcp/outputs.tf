output "otel_collector_url" {
  description = "URL pública del OTel Collector en Cloud Run (endpoint OTLP/HTTP)"
  value       = google_cloud_run_v2_service.otel_collector.uri
}

output "otel_collector_otlp_traces_endpoint" {
  description = "Endpoint completo para el exporter OTLP/HTTP de trazas"
  value       = "${google_cloud_run_v2_service.otel_collector.uri}/v1/traces"
}

output "cloud_trace_console_url" {
  description = "Consola de Cloud Trace para este proyecto"
  value       = "https://console.cloud.google.com/traces/list?project=${var.project_id}"
}
