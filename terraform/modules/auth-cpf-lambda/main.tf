locals {
  function_name = "${var.project_name}-auth-cpf"
  # AWS Academy (voclabs) nao permite iam:CreateRole/PutRolePolicy — so pode
  # USAR a LabRole pre-existente (ja tem as permissoes necessarias: logs,
  # ENI na VPC etc.). Mesmo padrao ja usado pelos nodes do EKS no bootstrap
  # (local.lab_role_arn).
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

data "aws_caller_identity" "current" {}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${var.dist_dir}/index.js"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

# --------------------------- REDE (SG da lambda) ----------------------------
# O SG do RDS (repo infra-db) libera ingress para toda a VPC_CIDR, entao
# a lambda so precisa de egress para alcancar o RDS, o Secrets Manager e a
# internet (via NAT, ja habilitado no bootstrap da VPC).
resource "aws_security_group" "lambda" {
  name        = "${local.function_name}-sg"
  description = "Egress da lambda de autenticacao por CPF"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.function_name}-sg"
  }
}

# ------------------------------- LAMBDA -------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  role             = local.lab_role_arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      JWT_PRIVATE_KEY = var.jwt_private_key_pem
      JWT_PUBLIC_KEY  = var.jwt_public_key_pem
      JWT_ISSUER      = var.jwt_issuer
      JWT_EXPIRES_IN  = tostring(var.jwt_expires_in)
      DB_HOST         = var.db_host
      DB_PORT         = tostring(var.db_port)
      DB_NAME         = var.db_name
      DB_USER         = var.db_user
      DB_PASSWORD     = var.db_password
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = local.function_name
  }
}

# Sem API Gateway proprio: a rota POST /auth/cpf vive no unico API Gateway do
# app (repo infra, modulo app-gateway), que le invoke_arn/function_name desta
# lambda via terraform_remote_state (outputs.tf) e cria a integracao +
# aws_lambda_permission de la. Mesmo padrao da jwt-authorizer-lambda.
