locals {
  function_name = "${var.project_name}-logs-forwarder"
}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = "${var.dist_dir}/logs-forwarder"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name    = local.function_name
  role             = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  handler          = "lata_velha_logs_forwarder.handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = {
      DD_API_KEY     = var.dd_api_key
      DD_SITE        = var.dd_site
      DD_ENV         = var.dd_env
      DD_SERVICE     = "lata-velha-edge"
      DD_VERSION     = var.service_version
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Name = local.function_name
  }
}

data "aws_caller_identity" "current" {}

# Permite que o CloudWatch Logs invoque o forwarder.
resource "aws_lambda_permission" "cloudwatch_logs" {
  statement_id  = "AllowCloudWatchLogsInvokeForwarder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${var.log_group_arn}:*"
}

# Assina o log group do API Gateway. filter_pattern vazio = todos os eventos.
resource "aws_cloudwatch_log_subscription_filter" "apigateway" {
  name            = "${local.function_name}-apigateway"
  log_group_name  = var.log_group_name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.cloudwatch_logs]
}
