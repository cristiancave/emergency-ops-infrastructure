# Password generado por Terraform: alfanumérico puro para no tener que
# URL-encodear caracteres especiales al armar la connection string.
resource "random_password" "triage_db" {
  length  = 32
  special = false
}

# Subnets privadas para la instancia RDS: nunca expuesta a internet.
resource "aws_db_subnet_group" "triage" {
  name       = "${var.project_name}-triage-db"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-triage-db-subnet-group"
  }
}

# Solo las tasks de ECS pueden hablarle a la base, y solo en el puerto de Postgres.
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for triage RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_db_instance" "triage" {
  identifier     = "${var.project_name}-triage-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.triage_db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "triage"
  username = "triage"
  password = random_password.triage_db.result

  db_subnet_group_name   = aws_db_subnet_group.triage.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                = false
  backup_retention_period = var.environment == "prod" ? 7 : 1
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  tags = {
    Name = "${var.project_name}-triage-db"
  }
}

# Connection string completa como un solo secreto: la app la lee como
# DATABASE_URL sin tener que ensamblar host/user/password por su cuenta.
resource "aws_secretsmanager_secret" "triage_db_url" {
  name = "${var.project_name}-triage-database-url"
  # dev/staging: permite recrear el secreto sin esperar el recovery window
  # por defecto (30 días). En prod se prefiere mantenerlo por seguridad.
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name = "${var.project_name}-triage-database-url"
  }
}

resource "aws_secretsmanager_secret_version" "triage_db_url" {
  secret_id     = aws_secretsmanager_secret.triage_db_url.id
  secret_string = "postgres://${aws_db_instance.triage.username}:${random_password.triage_db.result}@${aws_db_instance.triage.address}:${aws_db_instance.triage.port}/${aws_db_instance.triage.db_name}?sslmode=require"
}

# La managed policy de ejecución de ECS no incluye acceso a Secrets Manager;
# se lo damos acotado solo a este secreto.
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-secrets-access"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.triage_db_url.arn]
      }
    ]
  })
}
