# Emergency Ops - Infrastructure as Code

Infraestructura **multi-cloud** para desplegar y operar Emergency Ops: 2 microservicios
(`dispatch` → `triage`) instrumentados con OpenTelemetry corriendo en AWS, más un segundo OTel
Collector en GCP que recibe las mismas trazas en paralelo — todo definido en Terraform y
desplegado vía CI/CD.

El código de los servicios vive en [emergency-ops](https://github.com/cristiancave/emergency-ops).

## 📋 Requisitos

- Terraform >= 1.15 (la versión pineada en `.github/workflows/terraform.yml`)
- AWS CLI configurado con credenciales válidas (solo para operar manualmente / debugging — el
  despliegue normal lo hace CI/CD, no hace falta correr Terraform local)
- Cuenta AWS activa
- Cuenta GCP activa con billing (solo si vas a tocar `terraform-gcp/`)

## 🏗️ Estructura del repositorio

```
terraform/                     # AWS — la app completa vive acá
├── provider.tf              # AWS provider + backend S3 (estado remoto, ya configurado)
├── variables.tf              # Definición de variables
├── main.tf                   # VPC, subnets, IGW, NAT, ALB, security groups base
├── ecs.tf                    # Cluster ECS, task definitions y services de dispatch/triage
├── ecr.tf                    # Repositorios ECR (dispatch, triage) + lifecycle policy
├── db.tf                     # RDS PostgreSQL + Secrets Manager (connection string)
├── collector.tf              # OTel Collector (ECS Fargate, ADOT) + Cloud Map + IAM
├── monitoring.tf             # Prometheus + Grafana (ECS Fargate) + dashboard provisionado
├── outputs.tf                 # Outputs (URLs, ARNs, nombres de recursos)
├── terraform.tfvars           # Valores por defecto
└── environments/
    ├── dev.tfvars            # Ambiente actualmente desplegado
    ├── staging.tfvars
    └── prod.tfvars
terraform-gcp/                 # GCP — solo el segundo OTel Collector (ver sección abajo)
├── provider.tf               # google provider + backend GCS (estado separado del de AWS)
├── variables.tf
├── collector.tf               # Cloud Run: Collector -> Cloud Trace + Cloud Monitoring
└── outputs.tf
scripts/
└── generate-demo-traffic.ps1 # Genera tráfico mixto (2xx/4xx/5xx) contra el ALB para
                                # poblar Grafana/X-Ray/CloudWatch con datos reales
docs/
├── architecture.drawio        # Diagrama de arquitectura completo (abrir en app.diagrams.net)
├── Reporte_Tecnico_Emergency_Ops.docx  # Reporte técnico: arquitectura, decisiones, overhead
├── GITHUB_OIDC.md              # Cómo está configurado el IAM Role OIDC para CI/CD
├── ADR.md                      # Architecture Decision Records (16 decisiones documentadas)
├── SETUP.md                    # Guía de primeros pasos y operación del ambiente
└── EJEMPLOS.md                 # Comandos de referencia de Terraform
```

## 🚀 Cómo se despliega (CI/CD — flujo normal)

**No hace falta correr Terraform en tu máquina para desplegar.** El flujo real es:

1. Push a `main` en [emergency-ops](https://github.com/cristiancave/emergency-ops) → GitHub
   Actions corre los tests y, si pasan, hace build + push de las imágenes Docker a ECR (contexto
   de build = raíz del repo, porque ambos servicios comparten el módulo local `pkg/` vía
   `go.work`).
2. Push a `main` en **este repo** → GitHub Actions (`.github/workflows/terraform.yml`) corre
   `terraform fmt -check`, `validate`, `plan` y **`apply` automático** contra el ambiente `dev`.
3. Ambos workflows se autentican contra AWS vía **OIDC** (`docs/GITHUB_OIDC.md`) — no hay
   credenciales estáticas guardadas como secret en GitHub.

Si cambiaste solo Terraform (sin tocar código de los servicios), un push a este repo alcanza. Si
cambiaste código de los servicios, ese push ya deja las imágenes `:latest` listas en ECR, pero
**no** redeploya las tasks de ECS solo — para eso:

```bash
aws ecs update-service --cluster emergency-ops-cluster --service emergency-ops-dispatch --force-new-deployment --region us-east-1
aws ecs update-service --cluster emergency-ops-cluster --service emergency-ops-triage --force-new-deployment --region us-east-1
```

## 🛠️ Operar Terraform manualmente (debugging / iteración rápida)

```bash
cd terraform
terraform init                                            # backend S3 ya configurado
terraform plan -var-file="environments/dev.tfvars" -out=tfplan
terraform apply tfplan
terraform output
```

El estado remoto vive en S3 (`terraform-state-emergency-ops-149511939303`) con locking en
DynamoDB (`terraform-locks`) — ya está migrado y configurado en `provider.tf`, no hace falta
tocar nada para que funcione en equipo.

## 📊 Recursos que gestiona este Terraform

### Networking
- VPC (`10.0.0.0/16`), 2 subnets públicas + 2 privadas (2 AZs), Internet Gateway, 2 NAT Gateways
- Security groups por componente (ALB, ECS tasks, RDS, Collector, Prometheus, Grafana)
- AWS Cloud Map (`emergency-ops.local`) — DNS privado para que dispatch/triage/Collector/
  Prometheus se resuelvan entre sí sin depender de IPs de tarea (que cambian en cada deploy)

### Compute (ECS Fargate) — 5 servicios en `emergency-ops-cluster`
| Servicio | Rol |
|---|---|
| `emergency-ops-dispatch` | dispatch-service |
| `emergency-ops-triage` | triage-service |
| `emergency-ops-otel-collector` | OTel Collector (ADOT), recibe OTLP y exporta a X-Ray/Prometheus |
| `emergency-ops-prometheus` | Scrapea métricas de dispatch/triage/Collector |
| `emergency-ops-grafana` | Dashboard de SLIs |

### Base de datos
- RDS PostgreSQL (`db.t4g.micro`) en subnets privadas, sin acceso público
- Connection string generada por Terraform y guardada en Secrets Manager (nunca en texto plano
  en el código ni en tfvars)

### Contenedores
- 2 repositorios ECR (`emergency-ops-dispatch`, `emergency-ops-triage`) con lifecycle policy
  (mantiene las últimas 10 imágenes)

### Observabilidad
- OTel Collector: config en SSM Parameter Store, inyectada como env var al contenedor
- Prometheus: scrape config también vía SSM, mismo mecanismo
- Grafana: datasources (Prometheus + CloudWatch nativo) y dashboard *"Emergency Ops - SLIs"*
  (6 paneles) provisionados automáticamente al arrancar el contenedor
- AWS X-Ray como backend de trazas (exporter nativo del Collector)
- CloudWatch Logs (driver `awslogs`) + Container Insights para CPU/memoria real de los
  contenedores

## ☁️ Multi-cloud: segundo OTel Collector en GCP

`dispatch`/`triage` exportan cada traza **dos veces en paralelo**: al Collector de AWS (como
siempre) y a un segundo Collector desplegado en **Cloud Run** (GCP), vía la variable de entorno
`OTEL_EXPORTER_OTLP_ENDPOINT_GCP`. No es una app duplicada en GCP — es la misma app en AWS,
demostrando propagación de contexto cross-cloud con tráfico real, no un healthcheck aislado.

- **Collector**: `otel/opentelemetry-collector-contrib` en Cloud Run, receiver OTLP/HTTP (Cloud
  Run solo expone **un** puerto externo por servicio, a diferencia del ALB con múltiples
  listeners — por eso OTLP/HTTP, no gRPC, y por eso no hay Jaeger self-hosted acá, ver
  ADR-016).
- **Trazas**: exporter `googlecloud` → **Cloud Trace** (no Jaeger — Jaeger necesitaría 2 puertos
  externos que Cloud Run no puede dar en un mismo servicio).
- **Métricas**: mismo exporter `googlecloud` → **Cloud Monitoring**.
- **State**: bucket GCS propio (`terraform-state-emergency-ops-gcp-476583311075`), separado del
  de AWS.

Ver traza cruzando ambas nubes:
```bash
cd terraform-gcp && terraform output cloud_trace_console_url
# o vía API:
TOKEN=$(gcloud auth print-access-token)
curl -H "Authorization: Bearer $TOKEN" \
  "https://cloudtrace.googleapis.com/v1/projects/<PROJECT_ID>/traces/<TRACE_ID>"
```
El `<TRACE_ID>` es el mismo que ya sacás de los logs de CloudWatch (ver sección de arriba) — es
literalmente el mismo id, generado en AWS, visible en dos consolas de dos nubes distintas.

### Operar Terraform de GCP

```bash
cd terraform-gcp
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Requiere `gcloud auth login` + `gcloud auth application-default login` una vez por máquina.

### Load Balancing
- ALB con path-based routing (`/dispatch*` → dispatch, `/triage*` → triage) y un listener
  adicional en `:3000` → Grafana

### Seguridad / Config
- IAM roles con permisos mínimos por componente (no un rol único compartido)
- Secrets Manager: connection string de RDS, password de admin de Grafana (generado por
  Terraform, nunca hardcodeado)
- SSM Parameter Store: configuración de Collector/Prometheus/Grafana
- ECS Exec habilitado en `triage` (rol con permisos `ssmmessages:*`) para poder entrar a una
  shell del contenedor sin exponer la RDS a internet — ver sección de debugging abajo

## 📝 Variables principales

| Variable | Descripción | Default |
|----------|-------------|---------|
| `aws_region` | Región AWS | `us-east-1` |
| `environment` | Ambiente (dev/staging/prod) | — (requerida) |
| `vpc_cidr` | CIDR del VPC | `10.0.0.0/16` |
| `dispatch_cpu` / `dispatch_memory` | CPU/memoria de la task de dispatch | `256` / `512` |
| `triage_cpu` / `triage_memory` | CPU/memoria de la task de triage | `256` / `512` |
| `triage_db_instance_class` | Clase de instancia RDS | `db.t4g.micro` |
| `otel_collector_cpu` / `_memory` | CPU/memoria del Collector | `256` / `512` |
| `prometheus_cpu` / `_memory` | CPU/memoria de Prometheus | `256` / `512` |
| `grafana_cpu` / `_memory` | CPU/memoria de Grafana | `256` / `512` |
| `dispatch_image_uri` / `triage_image_uri` | URI de imagen en ECR (la actualiza CI/CD) | ver `dev.tfvars` |
| `enable_autoscaling` | Habilitar auto-scaling de dispatch/triage | `true` (`false` en dev) |

## 💰 Operar el ambiente — pausar/reanudar para no generar costo

Los NAT Gateways y el ALB no tienen estado "detenido" (solo se pueden borrar y recrear), pero el
cómputo (ECS Fargate) y la RDS sí:

**Pausar** (deja NAT Gateways + ALB corriendo, que son el costo fijo menor; corta el costo
variable de cómputo):
```bash
for svc in dispatch triage otel-collector prometheus grafana; do
  aws ecs update-service --cluster emergency-ops-cluster --service "emergency-ops-$svc" --desired-count 0 --region us-east-1
done
aws rds stop-db-instance --db-instance-identifier emergency-ops-triage-db --region us-east-1
```

**Reanudar**:
```bash
aws rds start-db-instance --db-instance-identifier emergency-ops-triage-db --region us-east-1
for svc in dispatch triage otel-collector prometheus grafana; do
  aws ecs update-service --cluster emergency-ops-cluster --service "emergency-ops-$svc" --desired-count 1 --region us-east-1
done
```

RDS detenida se reinicia sola a los 7 días si no la levantás vos — no es un problema si vas a
retomar en menos de una semana.

## 🔍 Generar tráfico de prueba

```powershell
.\scripts\generate-demo-traffic.ps1
.\scripts\generate-demo-traffic.ps1 -Rounds 10 -DelayMs 200   # más volumen
```

Dispara una mezcla de requests válidas (una por cada prioridad de triage) e inválidas (400/404,
y eventualmente 503 cuando se agota el pool de ambulancias de dispatch) para que Grafana, X-Ray
y CloudWatch Logs Insights muestren datos realistas, no solo el camino feliz.

## 🐛 Debugging: conectarse a la RDS sin exponerla a internet

`triage` tiene ECS Exec habilitado. Requiere el
[Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
instalado localmente.

```bash
TASK_ARN=$(aws ecs list-tasks --cluster emergency-ops-cluster --service-name emergency-ops-triage --desired-status RUNNING --region us-east-1 --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster emergency-ops-cluster --task "$TASK_ARN" \
  --container emergency-ops-triage --interactive --command "/bin/sh" --region us-east-1

# Dentro del contenedor (Alpine, sin cliente psql preinstalado):
apk add --no-cache postgresql-client
psql "$DATABASE_URL"
```

## 📈 Monitoreo y visualización

| Qué | Cómo |
|---|---|
| **Grafana** | `http://<alb_dns_name>:3000` — user `admin`, password: `aws secretsmanager get-secret-value --secret-id emergency-ops-grafana-admin-password --region us-east-1 --query SecretString --output text` |
| **Dashboard de SLIs** | `http://<alb_dns_name>:3000/d/emergency-ops-slis` |
| **X-Ray** | Consola AWS → `https://console.aws.amazon.com/xray/home?region=us-east-1#/traces` (o `aws xray get-trace-summaries`) |
| **CloudWatch Logs** | `aws logs tail /ecs/emergency-ops-dispatch --follow --region us-east-1` (y `-triage`, `-otel-collector`, `-prometheus`, `-grafana`) |
| **Container Insights** | CloudWatch → Container Insights → Clusters → `emergency-ops-cluster` |
| **Estado de los servicios** | `aws ecs describe-services --cluster emergency-ops-cluster --services emergency-ops-dispatch emergency-ops-triage emergency-ops-otel-collector emergency-ops-prometheus emergency-ops-grafana --region us-east-1` |

## 🧹 Destruir la infraestructura

```bash
terraform destroy -var-file="environments/dev.tfvars"
```

⚠️ Esto borra todo, incluida la RDS (sin snapshot final en `dev`, ver `db.tf` —
`skip_final_snapshot = var.environment != "prod"`).

## 📚 Documentación adicional

- [docs/architecture.drawio](docs/architecture.drawio) — diagrama de arquitectura completo
- [docs/Reporte_Tecnico_Emergency_Ops.docx](docs/Reporte_Tecnico_Emergency_Ops.docx) — reporte
  técnico: arquitectura, decisiones de diseño, análisis de overhead de OTel
- [docs/GITHUB_OIDC.md](docs/GITHUB_OIDC.md) — cómo está configurado el IAM Role OIDC
- [emergency-ops/docs/OTEL_OVERHEAD_BENCHMARK.md](https://github.com/cristiancave/emergency-ops/blob/main/docs/OTEL_OVERHEAD_BENCHMARK.md) —
  metodología y resultados completos del benchmark de overhead

## 📞 Soporte

Terraform: https://www.terraform.io/docs · AWS ECS: https://docs.aws.amazon.com/ecs/
