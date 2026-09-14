locals {
  function_name = "${var.project_name}-jwt-authorizer"
  # AWS Academy (voclabs) nao permite iam:CreateRole/PutRolePolicy — so pode
  # USAR a LabRole pre-existente. Mesmo padrao do modulo auth-cpf-lambda e
  # dos nodes do EKS no bootstrap (local.lab_role_arn).
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  # ------------------------------------------------------------------
  # D1 · Observabilidade Datadog — mesmas layers/envs do modulo
  # auth-cpf-lambda (ver comentario detalhado la). Conta 417141415827
  # = Datadog site us5.datadoghq.com.
  # ------------------------------------------------------------------
  datadog_extension_layer = "arn:aws:lambda:${var.region}:417141415827:layer:Datadog-Extension:${var.datadog_extension_layer_version}"
  datadog_python_layer    = "arn:aws:lambda:${var.region}:417141415827:layer:Datadog-Python312:${var.datadog_python_layer_version}"
}

data "aws_caller_identity" "current" {}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${var.dist_dir}/jwt-authorizer"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  role             = local.lab_role_arn
  # D1: handler redirecionado para o wrapper da layer Datadog-Python — o
  # handler original fica em DD_LAMBDA_HANDLER (environment abaixo).
  handler          = "datadog_lambda.handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  # D1: layers Datadog (Extension + Python). Aditivo — nao substitui nada.
  layers = [local.datadog_extension_layer, local.datadog_python_layer]

  # D1: X-Ray Active. Suportado em lambdas usadas como authorizer do
  # API Gateway (o trace cobre a invocacao da authorizer tambem).
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      # Handler original, empacotado pela layer datadog-lambda
      DD_LAMBDA_HANDLER = "lata_velha_auth.handlers.authorizer_handler.lambda_handler"
      JWT_PUBLIC_KEY    = var.jwt_public_key_pem
      JWT_ISSUER        = var.jwt_issuer

      # ---- D1 · Datadog (envio direto p/ site us5, sem Forwarder) ----
      DD_API_KEY                 = var.dd_api_key
      DD_SITE                    = var.dd_site
      DD_ENV                     = var.dd_env
      DD_VERSION                 = var.dd_version
      DD_SERVICE                 = local.function_name
      DD_TRACE_ENABLED           = "true"
      DD_LOGS_INJECTION          = "true"
      DD_SERVERLESS_LOGS_ENABLED = "true"
      DD_CAPTURE_LAMBDA_PAYLOAD  = "false"
      DD_EXTENSION_VERSION       = "next"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Name = local.function_name
  }
}
