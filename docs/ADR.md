# Architecture Decision Records (ADR)

## ADR-001: Infrastructure as Code with Terraform

### Status
ACCEPTED

### Context
We need to manage AWS infrastructure for the Emergency Ops microservices platform in a reproducible, version-controlled, and scalable manner.

### Decision
Use Terraform as the Infrastructure as Code tool for AWS management.

### Rationale
- **Multi-cloud capability**: Not locked into AWS
- **Large community**: Abundant resources and modules
- **State management**: Clear separation of concerns
- **Version control**: Full infrastructure history
- **Team collaboration**: Easy to review in pull requests

### Consequences
- Terraform state must be managed carefully
- Requires AWS IAM credentials
- Need to set up S3 backend for team environments
- Regular state backups recommended

---

## ADR-002: ECS Fargate for Container Orchestration

### Status
ACCEPTED

### Context
We need to run containerized microservices (Go applications) in AWS with minimal operational overhead.

### Decision
Use AWS ECS (Elastic Container Service) with Fargate launch type.

### Rationale
- **Serverless**: No need to manage EC2 instances
- **Cost-efficient**: Pay only for what you use
- **Easy integration**: ALB, Auto-scaling, CloudWatch
- **AWS-native**: Native integration with other AWS services
- **Security**: Automatic patching and updates

### Consequences
- Locked to AWS ecosystem
- Limited customization compared to Kubernetes
- Container size limited to 10GB
- Network throughput limits per task

---

## ADR-003: Application Load Balancer with Path-based Routing

### Status
ACCEPTED

### Context
Multiple microservices need to be exposed through a single entry point with intelligent routing.

### Decision
Use AWS Application Load Balancer (ALB) with path-based routing rules.

### Rationale
- **Path-based routing**: /dispatch → dispatch service, /triage → triage service
- **Auto-scaling friendly**: Works seamlessly with ECS Auto Scaling
- **Health checks**: Built-in health check capabilities
- **Cost**: Single ALB for multiple services

### Consequences
- Requires health check endpoints on services
- Path rewriting needed if services don't expect paths
- CloudWatch monitoring must be configured

---

## ADR-004: Multi-environment Strategy (Dev, Staging, Prod)

### Status
ACCEPTED

### Context
We need different configurations and resource allocations for different deployment environments.

### Decision
Separate tfvars files for dev, staging, and prod with different resource allocations.

### Rationale
- **Cost optimization**: Dev uses minimal resources, Prod uses HA setup
- **Testing**: Staging matches production closely
- **Risk isolation**: Dev/staging failures don't affect production
- **Gradual rollout**: Changes tested in multiple environments

### Consequences
- More tfvars files to maintain
- Need to track which file is used in each environment
- Risk of applying wrong environment configuration

---

## ADR-005: Auto-scaling Policy Based on CPU/Memory

### Status
ACCEPTED

### Context
Need automatic scaling to handle variable load on microservices.

### Decision
Use Target Tracking Scaling policies based on CPU and memory utilization.

### Rationale
- **Automatic**: No manual intervention needed
- **Predictable costs**: Scales up only when needed
- **Dual metrics**: CPU + Memory for comprehensive coverage
- **Easy tuning**: Simple adjustable thresholds

### Consequences
- Must ensure proper resource requests/limits
- Health checks must be accurate
- Scaling takes time (may not handle sudden spikes)

---

## ADR-006: CloudWatch Logs for Container Logging

### Status
ACCEPTED

### Context
Microservices need centralized, accessible logging for debugging and monitoring.

### Decision
Use CloudWatch Logs as the log driver for ECS containers.

### Rationale
- **AWS-native**: Seamless integration with ECS
- **No agent needed**: Built-in log driver
- **Searchable**: Full-text search capabilities
- **Retention policies**: Automatic cleanup

### Consequences
- Logs only available within AWS
- CloudWatch Insights required for complex queries
- Additional AWS costs for log storage

---

## ADR-007: VPC with Public/Private Subnets

### Status
ACCEPTED

### Context
Need proper network segmentation for security and best practices.

### Decision
Create VPC with 2-3 public subnets (ALB) and 2-3 private subnets (ECS tasks) per AZ.

### Rationale
- **Security**: ECS tasks not exposed to internet
- **HA**: Multiple availability zones for fault tolerance
- **NAT Gateways**: Secure outbound internet access
- **Best practices**: Following AWS Well-Architected Framework

### Consequences
- Increased infrastructure complexity
- NAT Gateway costs for outbound traffic
- More subnets to manage

---

## ADR-008: RDS PostgreSQL administrado en vez de contenedor en ECS

### Status
ACCEPTED

### Context
`triage-service` necesita persistencia real (reportes de emergencia y clasificaciones). Correr
Postgres en un contenedor dentro del mismo cluster ECS era la opción más barata y simple de
desplegar.

### Decision
Usar RDS PostgreSQL (`db.t4g.micro`) en vez de un contenedor Postgres en ECS.

### Rationale
- Backups automáticos y punto de restauración gestionados por AWS, sin implementarlos a mano.
- Es el estándar del ecosistema AWS para este caso de uso.
- No aumenta la superficie operativa del cluster de aplicación (parcheo del motor de DB,
  volúmenes persistentes, etc. quedan fuera de nuestra responsabilidad).

### Consequences
- Costo adicional frente a un contenedor (marginal en `db.t4g.micro`).
- Un componente más gestionado por Terraform (`db.tf`): subnet group, security group, secreto
  en Secrets Manager con la connection string.
- RDS solo se puede pausar (`stop-db-instance`, hasta 7 días) o destruir/recrear — no tiene un
  equivalente exacto a "escalar a 0" como ECS.

---

## ADR-009: AWS X-Ray como backend de trazas (no Jaeger/Tempo self-hosted)

### Status
ACCEPTED

### Context
El OTel Collector necesita exportar las trazas a algún backend con capacidad de búsqueda y
visualización. Las opciones evaluadas fueron Jaeger o Grafana Tempo self-hosted en ECS, versus
AWS X-Ray como servicio administrado.

### Decision
Usar AWS X-Ray, vía el exporter nativo `awsxray` del OTel Collector.

### Rationale
- Cero infraestructura adicional que mantener ni almacenamiento propio que dimensionar.
- Exporter de primera clase en la distribución ADOT del Collector.
- Para un proyecto ya desplegado íntegramente en AWS, el acoplamiento adicional a AWS no es un
  costo real.

### Consequences
- Menos portable que un backend basado en el estándar OTLP si algún día se quisiera migrar de
  nube.
- La visualización de trazas vive en la consola de AWS, separada de Grafana (que sí es donde
  viven las métricas) — la correlación entre ambas se hace por `trace_id` manualmente, no hay
  un link directo entre Grafana y X-Ray.

---

## ADR-010: Prometheus + Grafana self-hosted (no Amazon Managed Prometheus/Grafana)

### Status
ACCEPTED

### Context
Para las métricas, a diferencia de las trazas, sí se evaluó y se descartó ir 100% managed.

### Decision
Desplegar Prometheus y Grafana como contenedores propios en ECS Fargate (`monitoring.tf`), en
vez de usar Amazon Managed Service for Prometheus (AMP) y Amazon Managed Grafana (AMG).

### Rationale
- El pricing de AMP/AMG es por volumen de métricas ingeridas y por usuario activo — para un
  proyecto de bajo tráfico y de aprendizaje, self-hosted es más barato.
- Correr el stack completo (scrape config, provisioning de dashboards y datasources) da más
  visibilidad de cómo funciona un pipeline de métricas real, en vez de delegarlo a un servicio
  caja negra.

### Consequences
- Hay que operar 2 servicios ECS más (Prometheus, Grafana) — más superficie de configuración y
  de fallas potenciales que un servicio administrado.
- Sin alta disponibilidad ni retención a largo plazo out-of-the-box (Prometheus corre 1 sola
  réplica, sin almacenamiento remoto) — aceptable para `dev`, a revisar antes de producción.
- Ninguna de las dos imágenes oficiales (`prom/prometheus`, `grafana/grafana`) sabe leer su
  configuración desde una variable de entorno nativamente → ver ADR-011.

---

## ADR-011: Entrega de configuración a Collector/Prometheus/Grafana vía SSM + entrypoint override

### Status
ACCEPTED

### Context
El OTel Collector (ADOT), Prometheus y Grafana necesitan su archivo de configuración
(`config.yaml`, `prometheus.yml`, datasources/dashboards de Grafana) dentro del contenedor. La
alternativa más común — hornear una imagen custom con el archivo incluido — implica un pipeline
de build y push adicional por cada uno de los tres componentes.

Primer intento fallido: la distribución ADOT del Collector documenta (o al menos así se
interpretó) soporte para `--config=ssm:<parametro>`, leyendo la config directo desde SSM
Parameter Store. En la práctica falló con `unsupported scheme on URI "ssm:..."` — ese config
provider no está disponible en esta imagen/versión.

### Decision
Guardar cada configuración como parámetro en SSM Parameter Store, inyectarla como variable de
entorno en la task definition de ECS (mecanismo `secrets`, que sí soporta referenciar SSM
directamente), y sobreescribir el `command`/`entrypoint` del contenedor para que escriba esa
variable a un archivo en disco antes de arrancar el proceso real:

- Collector: usa el config provider estándar `env:` (`--config=env:OTEL_COLLECTOR_CONFIG_YAML`).
- Prometheus/Grafana: no soportan ningún provider de config vía env var, así que el
  `entryPoint` se reemplaza por `["/bin/sh", "-c"]` con un comando que escribe el archivo y
  termina con `exec` al binario/entrypoint real de la imagen.

### Rationale
- Evita mantener 3 pipelines de build de imágenes custom solo para inyectar un archivo de
  config.
- Reutiliza el mismo mecanismo (SSM + secrets de ECS) para los tres componentes, un solo patrón
  para entender y mantener.
- El histórico de cambios de la configuración queda versionado en el propio parámetro de SSM
  (y en Terraform, que es quien lo escribe).

### Consequences
- El `entryPoint` override es frágil frente a cambios de la imagen oficial (si el entrypoint
  real cambia de `/run.sh` a otra ruta, por ejemplo, se rompe silenciosamente).
- Un cambio de configuración requiere forzar un nuevo deployment de la task (el contenedor no
  relee la variable de entorno en caliente).

---

## ADR-012: Autenticación de CI/CD vía GitHub OIDC, sin access keys estáticas

### Status
ACCEPTED

### Context
GitHub Actions necesita permisos en AWS para hacer `docker push` a ECR y `terraform apply`. La
opción tradicional es guardar `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` como secrets de
GitHub.

### Decision
Usar autenticación federada OIDC: un IAM Role con trust policy hacia
`token.actions.githubusercontent.com`, scopeado por nombre de repo/rama/tipo de evento. GitHub
Actions asume ese rol al vuelo, con credenciales que expiran en 1 hora.

### Rationale
- No hay credenciales de larga duración que puedan filtrarse o quedar en el historial de un
  secret mal rotado.
- Auditoría completa en CloudTrail de cada assume-role.
- Estándar recomendado por AWS y GitHub para este caso de uso.

### Consequences
- El trust policy es más delicado de configurar que pegar dos secrets — en particular, GitHub
  emite el claim `sub` del token con IDs numéricos inmutables del owner/repo, no solo el
  nombre (`repo:owner@ID/repo@ID:ref:...`), lo cual obligó a usar wildcards en el trust policy
  en vez de un match exacto por nombre.
- Cualquier repo/rama nuevo que necesite desplegar requiere tocar el trust policy del rol.

---

## ADR-013: Módulo Go compartido (`go.work`) y su consecuencia en el contexto de build de Docker

### Status
ACCEPTED

### Context
La configuración de telemetría OTel, el logger estructurado y el cliente HTTP instrumentado son
idénticos entre `dispatch-service` y `triage-service`. Duplicar ese código en cada servicio era
la alternativa más simple de desplegar (cada Dockerfile sigue buildeando con contexto =
directorio del servicio).

### Decision
Extraer ese código común a un módulo Go local (`pkg/`), referenciado por ambos servicios vía
`go.work` (Go workspaces).

### Rationale
- Un solo lugar donde corregir/evolucionar la configuración de OTel para ambos servicios.
- Evita que `dispatch` y `triage` diverjan silenciosamente en cómo instrumentan.

### Consequences
- El contexto de build de Docker tuvo que cambiar de "directorio del servicio" a "raíz del
  repositorio" — `pkg/` es un directorio hermano invisible para Docker con un contexto más
  acotado. Esto rompió el pipeline de CI/CD la primera vez que se agregó la dependencia a
  `pkg/`, hasta corregir los Dockerfiles y el workflow.
- `.dockerignore` pasó a vivir en la raíz del repo (Docker lo busca en la raíz del contexto,
  no en el directorio del servicio).

---

## ADR-014: Logs estructurados a stdout/CloudWatch, no señal OTLP de logs

### Status
ACCEPTED

### Context
OpenTelemetry define una tercera señal (logs) que también se puede exportar vía OTLP a través
del Collector, igual que trazas y métricas.

### Decision
No usar la señal OTLP de logs. En su lugar: logging estructurado JSON a stdout (con
`trace_id`/`span_id` inyectados desde el contexto activo), recolectado por el driver `awslogs`
de ECS hacia CloudWatch Logs.

### Rationale
- ECS ya provee recolección de logs de stdout de forma nativa — no hay que instrumentar nada
  adicional para eso.
- Evita agregar una tercera señal al pipeline del Collector (más superficie de configuración y
  de fallas).
- La correlación log↔traza (el requisito real de la Fase 3) se logra igual con el campo
  `trace_id` en el JSON, sin necesitar que el transporte sea específicamente OTLP.

### Consequences
- Los logs quedan atados a CloudWatch — si algún día se migra a otro backend de logs
  (Elasticsearch, Loki), hay que cambiar el log driver de las task definitions, no solo un
  exporter del Collector.
- No hay procesamiento/enriquecimiento de logs en el Collector (batching, filtrado) como sí lo
  hay para trazas y métricas.

---

## ADR-015: ECS Exec para debugging de la RDS, no exposición pública temporal

### Status
ACCEPTED

### Context
Se necesitaba poder inspeccionar el contenido de la RDS puntualmente (ej. con `psql` o una
herramienta GUI tipo HeidiSQL). La RDS vive en subnet privada sin IP pública. La alternativa más
rápida de armar es hacerla `publicly_accessible = true` temporalmente y abrir el security group
a una IP específica.

### Decision
Habilitar ECS Exec (`enable_execute_command = true`) en el servicio de `triage`, con un IAM
role con permisos `ssmmessages:*`, y conectarse vía `aws ecs execute-command` a una shell dentro
del contenedor — que ya tiene red hacia la RDS — instalando `postgresql-client` al vuelo con
`apk add`.

### Rationale
- La RDS nunca queda expuesta a internet, ni siquiera temporalmente.
- No depende de recordar revertir un cambio de security group/`publicly_accessible` después de
  terminar de debuggear.
- Reutiliza credenciales que el contenedor ya tiene (`DATABASE_URL` como variable de entorno),
  sin tener que copiar la contraseña a ningún otro lado.

### Consequences
- Requiere el Session Manager Plugin instalado localmente (`aws ecs execute-command` depende de
  él).
- No sirve para herramientas GUI que solo hablan TCP directo (ej. HeidiSQL) — para eso sí haría
  falta la alternativa de exposición temporal, evaluada y descartada para este proyecto.
- Cliente `psql` no viene preinstalado en la imagen (Alpine minimalista) — hay que instalarlo en
  cada sesión de exec, no queda persistido entre redeploys.

---

## ADR-016: Segundo OTel Collector en GCP (Cloud Run) con Cloud Trace en vez de Jaeger

### Status
ACCEPTED

### Context
El enunciado original describe el Collector desplegado en dos nubes en paralelo — "GCP: Cloud
Run o GKE. AWS: ECS Fargate" — con Jaeger UI como backend de trazas nombrado explícitamente para
el lado GCP. La app (`dispatch`/`triage`) sigue corriendo enteramente en AWS; lo que se evaluó
acá fue cómo sumar el segundo Collector sin migrar toda la aplicación.

Al intentar desplegar Jaeger en Cloud Run apareció una limitación real de la plataforma: un
servicio de Cloud Run expone **un solo puerto externo**. Jaeger necesita dos alcanzables desde
afuera — 16686 (UI) y 4317/4318 (receiver OTLP) — y no hay forma de exponer ambos en el mismo
servicio sin backends compartidos (que Jaeger self-hosted, con storage en memoria, no tiene) o
sin pasar a GKE.

### Decision
Desplegar el Collector en Cloud Run con receiver OTLP/HTTP como único puerto expuesto, y
exportar trazas y métricas al `googlecloud` exporter (**Cloud Trace** + **Cloud Monitoring**) en
vez de a un Jaeger self-hosted. La app en AWS manda cada traza dos veces en paralelo: al
Collector de AWS (como siempre) y a este de GCP, vía un segundo exporter OTLP/HTTP registrado en
el mismo `TracerProvider` (`pkg/telemetry.go`, campo `GCPOTLPEndpoint`).

### Rationale
- Mismo razonamiento que ADR-009 (X-Ray en vez de Jaeger/Tempo self-hosted para AWS): preferir
  el backend de trazas administrado de la nube en cuestión evita infraestructura propia — acá,
  además, evita un problema real de la plataforma (el límite de un puerto de Cloud Run), no solo
  una preferencia de menor mantenimiento.
- GKE sí resuelve el problema de multi-puerto (un `Service` de Kubernetes puede exponer varios),
  pero implica un cluster con costo fijo de control plane (~$70/mes) solo para desplegar un
  Collector — desproporcionado frente al resto de la infraestructura del proyecto.
- Mandar tráfico real de la app (no un ping aislado) al segundo Collector demuestra propagación
  de contexto cross-cloud de verdad: el mismo `trace_id` generado en un pod de ECS (AWS) es
  buscable en la consola de Cloud Trace (GCP) — verificado end-to-end antes de dar el trabajo
  por cerrado.

### Consequences
- El backend de trazas de GCP técnicamente no es "Jaeger" como nombra el enunciado original —
  es una sustitución justificada por una limitación de plataforma, no una decisión arbitraria.
- Dos state de Terraform completamente separados (`terraform/` en S3, `terraform-gcp/` en GCS),
  dos proveedores, dos ciclos de vida — más superficie que mantener a cambio de la cobertura
  multi-cloud.
- El export a GCP usa OTLP/HTTP con TLS (no gRPC interno como en AWS) porque Cloud Run necesita
  HTTPS público y el cliente Go de OTLP/gRPC-con-TLS-a-través-de-un-proxy-serverless tiene más
  aristas que simplemente usar `otlptracehttp`.
- Es un exporter *best-effort* adicional: si el Collector de GCP no está disponible, no afecta
  el pipeline principal de AWS (son batchers independientes en el mismo `TracerProvider`).

---

## ADR-017: Exemplars en `/metrics` para correlación métricas ↔ trazas

### Status
ACCEPTED

### Context
La correlación cross-signal ya cubría trazas ↔ logs (`trace_id` en los logs JSON, ver
ADR-anterior sobre logging estructurado) y trazas ↔ trazas cross-cloud (ADR-016), pero faltaba
la tercera pata: métricas ↔ trazas. Sin eso, un pico en el panel de p99 latency de Grafana no
tiene forma de llevar directo a una traza concreta que lo explique — hay que ir a buscarla a
mano por rango de tiempo.

El SDK de OTel para Go ya captura **exemplars** por default (desde v1.31 aprox., estable, no
experimental): cada medición de un histograma hecha con un span activo en el contexto queda
como candidata a exemplar (`exemplar.TraceBasedFilter`, el filtro default), sin tocar código de
instrumentación. El exporter de Prometheus (`go.opentelemetry.io/otel/exporters/prometheus`)
también sabe serializarlos — la única pieza que faltaba era la exposición: el formato de texto
clásico de Prometheus no puede llevar exemplars, solo **OpenMetrics** sí.

### Decision
- `pkg/telemetry.go`: cambiar el handler de `/metrics` de `promhttp.Handler()` (formato clásico)
  a `promhttp.HandlerFor(prometheus.DefaultGatherer, promhttp.HandlerOpts{EnableOpenMetrics:
  true})`.
- Prometheus (`terraform/monitoring.tf`): agregar el flag `--enable-feature=exemplar-storage` —
  sin él, Prometheus descarta los exemplars del scrape aunque vengan en el payload.
- Grafana: en el datasource de Prometheus, `jsonData.exemplarTraceIdDestinations` con un link
  externo a la consola de X-Ray parametrizado por `trace_id` (no hay datasource nativo de trazas
  para X-Ray tipo Tempo/Jaeger, así que el link es una URL directa en vez de una integración de
  datasource-a-datasource).

### Rationale
- No hizo falta tocar la instrumentación de negocio (spans custom, otelhttp, otelsql) — los
  exemplars son un efecto automático de tener trazas + métricas ya cableadas correctamente sobre
  el mismo contexto, que es justo lo que este proyecto ya tenía. El gap era puramente de
  exposición/formato, no de datos.
- Alternativa descartada: correlacionar a mano en Grafana vía time range + `trace_id` buscado en
  logs — funciona, pero es exactamente el flujo manual que un exemplar-link automatiza.

### Consequences
- El link del exemplar apunta a la consola de X-Ray, no a un panel embebido de Grafana — un
  click extra respecto a tener Tempo/Jaeger como datasource nativo, mismo tradeoff ya aceptado
  en ADR-016 por la limitación de Cloud Run.
- OpenMetrics es un superset compatible del formato de texto de Prometheus — no rompe scrapers
  existentes que no pidan explícitamente ese `Accept` header.

