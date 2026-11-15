locals {
  function_name = "${var.project_name}-jwt-authorizer"
  # AWS Academy (voclabs) nao permite iam:CreateRole/PutRolePolicy — so pode
  # USAR a LabRole pre-existente. Mesmo padrao do modulo auth-cpf-lambda e
  # dos nodes do EKS no bootstrap (local.lab_role_arn).
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
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
  handler          = "lata_velha_auth.handlers.authorizer_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  # Datadog Lambda Extension: traces/logs da authorizer (Story 20.1).
  layers = [
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension:${var.dd_extension_version}",
  ]

  environment {
    variables = {
      JWT_PUBLIC_KEY = var.jwt_public_key_pem
      JWT_ISSUER     = var.jwt_issuer

      # Datadog serverless (Story 20.1)
      DD_API_KEY                         = var.dd_api_key
      DD_SITE                            = var.dd_site
      DD_ENV                             = var.environment
      DD_SERVICE                         = local.function_name
      DD_VERSION                         = var.service_version
      DD_TRACE_ENABLED                   = "true"
      DD_LOGS_INJECTION                  = "true"
      DD_SERVERLESS_LOGS_ENABLED         = "true"
      DD_TRACE_PROPAGATION_STYLE_EXTRACT = "datadog,tracecontext"
      DD_TRACE_PROPAGATION_STYLE_INJECT  = "datadog,tracecontext"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Name = local.function_name
  }
}
