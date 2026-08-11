# Le os outputs do bootstrap (repo infra) para obter vpc_id/subnets privadas
# e do infra-db para obter o endpoint/credenciais do RDS — a lambda roda na
# mesma VPC do banco (o SG do RDS ja libera ingress para toda a VPC_CIDR).
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.bootstrap_state_key
    region = var.region
  }
}

data "terraform_remote_state" "infra_db" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.infra_db_state_key
    region = var.region
  }
}

# Le o api_id/execution_arn do API Gateway ja criado pelo repo infra (addons)
# — o "casco" do gateway (API + VPC Link + Stage) e' criado la, sem nenhuma
# rota. Este repo anexa a propria rota (POST /auth/cpf + o GET do OpenAPI
# dela) e a authorizer, direto aqui, sem precisar que o addons saiba nada
# sobre lambda.
data "terraform_remote_state" "addons" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.addons_state_key
    region = var.region
  }
}

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
  infra_db  = data.terraform_remote_state.infra_db.outputs
  addons    = data.terraform_remote_state.addons.outputs

  # rds_endpoint vem como "host:porta"
  db_host = split(":", local.infra_db.rds_endpoint)[0]
  db_port = tonumber(split(":", local.infra_db.rds_endpoint)[1])
}

# Fonte unica da chave JWT (RS256) e das credenciais do banco para a lambda —
# passadas direto como variavel de ambiente da function (sem Secrets Manager,
# ver lambda/README.md). A chave privada aqui PRECISA ser a mesma configurada
# em app.key/app.pub no app (JwtConfig.java) — do contrario o JwtDecoder do
# app rejeita os tokens emitidos por esta function.
module "auth_cpf_lambda" {
  source = "../modules/auth-cpf-lambda"

  project_name       = var.project_name
  vpc_id             = local.bootstrap.vpc_id
  private_subnet_ids = local.bootstrap.private_subnet_ids
  dist_dir           = "${path.module}/../../build"
  timeout            = var.lambda_timeout
  memory_size        = var.lambda_memory_size

  jwt_private_key_pem = var.jwt_private_key_pem
  jwt_issuer          = var.jwt_issuer
  jwt_expires_in      = var.jwt_expires_in
  db_host             = local.db_host
  db_port             = local.db_port
  db_name             = local.infra_db.db_name
  db_user             = local.infra_db.db_username
  db_password         = local.infra_db.db_password
}

# --------------------------------------------------------------------------
# Lambda authorizer do API Gateway do app (repo infra). Duplica, na borda,
# a mesma verificacao de assinatura/issuer/expiracao que o JwtDecoder do app
# ja faz — nao decide autorizacao por role, isso continua 100% no
# SecurityConfig do app. Recebe so a chave publica RSA + issuer (mesma da
# lambda auth-cpf) como variavel de ambiente — sem chave privada, sem
# credenciais do banco.
#
# A funcao E a anexacao dela ao API Gateway (aws_apigatewayv2_authorizer,
# aws_lambda_permission) sao criadas aqui mesmo — o "casco" do gateway
# (API + VPC Link + Stage) vem pronto do repo infra (addons) via
# terraform_remote_state, sem nenhuma rota. Pipeline: infra bootstrap ->
# infra addons -> infra-db -> lambda (aqui) -> app.
# --------------------------------------------------------------------------

module "jwt_authorizer_lambda" {
  source = "../modules/jwt-authorizer-lambda"

  project_name       = var.project_name
  dist_dir           = "${path.module}/../../build"
  jwt_public_key_pem = var.jwt_public_key_pem
  jwt_issuer         = var.jwt_issuer
}

# --------------------------------------------------------------------------
# Anexacao no API Gateway compartilhado (repo infra, addons): rota publica
# POST /auth/cpf (+ o GET do OpenAPI dela) na lambda auth-cpf, e a lambda
# authorizer registrada como aws_apigatewayv2_authorizer pras rotas
# protegidas que o repo app vai criar (app le jwt_authorizer_id daqui via
# remote_state).
# --------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "auth_cpf" {
  api_id                 = local.addons.app_api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.auth_cpf_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id    = local.addons.app_api_id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpf"
  action        = "lambda:InvokeFunction"
  function_name = module.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/*/POST/auth/cpf"
}

# A mesma lambda tambem serve o OpenAPI do POST /auth/cpf em GET, pro Swagger
# UI do app (springdoc.swagger-ui.urls) — sem precisar de copia estatica no
# repo app. Rota publica de proposito, e so documentacao.
resource "aws_apigatewayv2_route" "auth_cpf_openapi" {
  api_id    = local.addons.app_api_id
  route_key = "GET /auth/cpf-openapi.json"
  target    = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf_openapi" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpfOpenapi"
  action        = "lambda:InvokeFunction"
  function_name = module.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/*/GET/auth/cpf-openapi.json"
}

# Duplica na borda a verificacao de assinatura/issuer/expiracao do JWT que o
# app ja faz. Nao decide por role, so rejeita cedo tokens invalidos/ausentes
# antes de gastar um hop ate o ALB/pod. Autorizacao por role continua 100%
# no SecurityConfig do app.
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                            = local.addons.app_api_id
  name                              = "${var.project_name}-jwt-authorizer"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = module.jwt_authorizer_lambda.invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_result_ttl_in_seconds  = 30
}

resource "aws_lambda_permission" "app_gateway_invoke_authorizer" {
  statement_id  = "AllowAppApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = module.jwt_authorizer_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}
