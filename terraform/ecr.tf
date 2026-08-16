# ECR Repository for Dispatch Service
resource "aws_ecr_repository" "dispatch" {
  name                 = "${var.project_name}-dispatch"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-dispatch-ecr"
  }
}

# ECR Repository for Triage Service
resource "aws_ecr_repository" "triage" {
  name                 = "${var.project_name}-triage"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-triage-ecr"
  }
}

# Lifecycle policy: mantener solo las últimas 10 imágenes, limpiar el resto
resource "aws_ecr_lifecycle_policy" "dispatch" {
  repository = aws_ecr_repository.dispatch.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "triage" {
  repository = aws_ecr_repository.triage.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
