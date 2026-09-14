locals {
  function_name = "${var.project_name}-auth-cpf"
  # AWS Academy (voclabs) nao permite iam:CreateRole/PutRolePolicy — so pode
  # USAR a LabRole pre-existente (ja tem as permissoes necessarias: logs,
  # ENI na VPC etc.). Mesmo padrao ja usado pelos nodes do EKS no bootstrap
  # (local.lab_role_arn).
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  # ------------------------------------------------------------------
  # D1 · Observabilidade Datadog (traces + métricas + logs)
  # Duas layers oficiais, pinadas por variavel (ver CHANGELOG do
  # datadog-lambda-py em github.com/DataDog/datadog-lambda-python):
  #   - Datadog-Extension : agente que envia traces/metricas/logs direto
  #                         para o site Datadog (us5) sem Forwarder
  #   - Datadog-Python312 : camada datadog-lambda (ddtrace) que empacota o
  #                         handler e gera o trace APM da invocacao
  # Conta 417141415827 = Datadog site us5.datadoghq.com. Se o site mudar,
  # verificar a tabela de ARNs por site na doc oficial do Datadog.
  # ------------------------------------------------------------------
  datadog_extension_layer = "arn:aws:lambda:${var.region}:417141415827:layer:Datadog-Extension:${var.datadog_extension_layer_version}"
  datadog_python_layer    = "arn:aws:lambda:${var.region}:417141415827:layer:Datadog-Python312:${var.datadog_python_layer_version}"
}

data "aws_caller_identity" "current" {}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${var.dist_dir}/auth-cpf"
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
  # D1: handler redirecionado para o wrapper da layer Datadog-Python — o
  # handler original fica em DD_LAMBDA_HANDLER (environment abaixo) e a
  # datadog-lambda empacota a invocacao para gerar o trace APM.
  handler          = "datadog_lambda.handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  # D1: layers Datadog (Extension + Python). Aditivo — nao substitui nada.
  layers = [local.datadog_extension_layer, local.datadog_python_layer]

  # D1: X-Ray Active para correlacao service↔lambda no Datadog APM.
  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      # Handler original, empacotado pela layer datadog-lambda
      DD_LAMBDA_HANDLER = "lata_velha_auth.handlers.auth_cpf_handler.lambda_handler"
      JWT_PRIVATE_KEY   = var.jwt_private_key_pem
      JWT_ISSUER        = var.jwt_issuer
      JWT_EXPIRES_IN    = tostring(var.jwt_expires_in)
      DB_HOST           = var.db_host
      DB_PORT           = tostring(var.db_port)
      DB_NAME           = var.db_name
      DB_USER           = var.db_user
      DB_PASSWORD       = var.db_password

      # ---- D1 · Datadog ----
      # Envio direto para o site Datadog (sem Forwarder): a Extension v88+
      # coleta logs do stdout. A lambda roda em subnet privada com NAT
      # (ver comment do SG acima), entao ha saida para a internet.
      DD_API_KEY                  = var.dd_api_key
      DD_SITE                     = var.dd_site
      DD_ENV                      = var.dd_env
      DD_VERSION                  = var.dd_version
      DD_SERVICE                  = local.function_name
      DD_TRACE_ENABLED            = "true"
      DD_LOGS_INJECTION           = "true"
      DD_SERVERLESS_LOGS_ENABLED  = "true"
      DD_CAPTURE_LAMBDA_PAYLOAD   = "false"
      DD_EXTENSION_VERSION        = "next"
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
