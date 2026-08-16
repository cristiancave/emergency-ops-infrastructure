# ==============================================================
# OTel Collector en Cloud Run.
#
# Cloud Run solo expone UN puerto externo por servicio (a diferencia de
# un ALB con múltiples listeners), así que el receiver OTLP/HTTP (4318)
# es el único puerto público; el receiver gRPC (4317) queda declarado
# pero no es alcanzable desde afuera. Por eso dispatch/triage (AWS) le
# mandan trazas vía OTLP/HTTP, no gRPC, para este segundo exporter.
#
# Exporta a Cloud Trace + Cloud Monitoring (exporter nativo "googlecloud")
# en vez de a un Jaeger self-hosted: Jaeger necesitaría 2 puertos externos
# (UI + receiver OTLP) que Cloud Run no puede exponer en un mismo
# servicio sin pasar a GKE. Mismo razonamiento que llevó a elegir X-Ray
# managed en vez de Tempo/Jaeger self-hosted para AWS (ver ADR-009).
# ==============================================================

resource "google_service_account" "otel_collector" {
  account_id   = "otel-collector"
  display_name = "OTel Collector (Cloud Run)"
}

resource "google_project_iam_member" "otel_collector_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

resource "google_project_iam_member" "otel_collector_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

locals {
  otel_collector_config = yamlencode({
    receivers = {
      otlp = {
        protocols = {
          grpc = { endpoint = "0.0.0.0:4317" } # no expuesto externamente por Cloud Run
          http = { endpoint = "0.0.0.0:4318" } # puerto público del servicio
        }
      }
    }

    processors = {
      memory_limiter = {
        check_interval  = "1s"
        limit_mib       = 400
        spike_limit_mib = 100
      }
      resource = {
        attributes = [
          {
            key    = "deployment.environment"
            value  = var.environment
            action = "upsert"
          },
          {
            key    = "cloud.provider"
            value  = "gcp"
            action = "upsert"
          }
        ]
      }
      batch = {
        timeout         = "5s"
        send_batch_size = 512
      }
    }

    exporters = {
      googlecloud = {
        project = var.project_id
      }
    }

    extensions = {
      health_check = { endpoint = "0.0.0.0:13133" }
    }

    service = {
      extensions = ["health_check"]
      pipelines = {
        traces = {
          receivers  = ["otlp"]
          processors = ["memory_limiter", "resource", "batch"]
          exporters  = ["googlecloud"]
        }
        metrics = {
          receivers  = ["otlp"]
          processors = ["memory_limiter", "resource", "batch"]
          exporters  = ["googlecloud"]
        }
      }
    }
  })
}

resource "google_cloud_run_v2_service" "otel_collector" {
  name     = "emergency-ops-otel-collector"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"
  # El provider de Google protege Cloud Run contra "terraform destroy" por
  # default. Este recurso es de laboratorio (mismo criterio que
  # skip_final_snapshot/recovery_window_in_days=0 del lado AWS) — se
  # necesita poder destruirlo limpio con un solo comando.
  deletion_protection = false

  template {
    service_account = google_service_account.otel_collector.email

    containers {
      image = "docker.io/otel/opentelemetry-collector-contrib:latest"

      args = ["--config=env:OTEL_COLLECTOR_CONFIG_YAML"]

      env {
        name  = "OTEL_COLLECTOR_CONFIG_YAML"
        value = local.otel_collector_config
      }

      ports {
        container_port = 4318
      }

      resources {
        limits = {
          cpu    = var.collector_cpu
          memory = var.collector_memory
        }
      }
    }
  }
}

# Acceso público: dispatch/triage (AWS) le mandan trazas por internet,
# no hay red privada compartida entre ambas clouds.
resource "google_cloud_run_v2_service_iam_member" "otel_collector_public" {
  name     = google_cloud_run_v2_service.otel_collector.name
  location = google_cloud_run_v2_service.otel_collector.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
