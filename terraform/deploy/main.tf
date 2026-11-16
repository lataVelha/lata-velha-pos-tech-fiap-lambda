# Le os outputs do bootstrap (repo infra) para obter vpc_id/subnets privadas
# e do os-service para obter endpoint/credenciais do RDS PROPRIO do os-service.
# A lambda roda na mesma VPC do banco (o SG do RDS do os-service libera
# ingress para toda a VPC_CIDR).
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.bootstrap_state_key
    region = var.region
  }
}

data "terraform_remote_state" "os_service" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = var.os_service_state_key
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
  bootstrap  = data.terraform_remote_state.bootstrap.outputs
  os_service = data.terraform_remote_state.os_service.outputs
  addons     = data.terraform_remote_state.addons.outputs

  # rds_endpoint vem como "host:porta"
  db_host = split(":", local.os_service.rds_endpoint)[0]
  db_port = tonumber(split(":", local.os_service.rds_endpoint)[1])
}

# Fonte unica da chave JWT (RS256) e das credenciais do banco do os-service
# para a lambda — passadas direto como variavel de ambiente da function (sem
# Secrets Manager, ver lambda/README.md). A chave privada aqui PRECISA ser a
# mesma configurada em app.key/app.pub no os-service (JwtConfig.java) — do
# contrario o JwtDecoder do os-service rejeita os tokens emitidos aqui.
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
  db_name             = local.os_service.db_name
  db_user             = local.os_service.db_username
  db_password         = local.os_service.db_password
}

# --------------------------------------------------------------------------
# Lambda authorizer do API Gateway. Duplica, na borda, a mesma verificacao
# de assinatura/issuer/expiracao que o JwtDecoder do os-service ja faz — nao
# decide autorizacao por role, isso continua 100% no SecurityConfig do
# os-service. Recebe so a chave publica RSA + issuer — sem chave privada,
# sem credenciais do banco.
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
# protegidas que o stack edge cria.
# --------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "auth_cpf" {
  api_id                 = local.addons.app_api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = module.auth_cpf_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id             = local.addons.app_api_id
  route_key          = "POST /auth/cpf"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpf"
  action        = "lambda:InvokeFunction"
  function_name = module.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/*/POST/auth/cpf"
}

# A mesma lambda tambem serve o OpenAPI do POST /auth/cpf em GET, pro
# Swagger UI (springdoc.swagger-ui.urls) — sem precisar de copia estatica.
# Rota publica de proposito, e so documentacao.
resource "aws_apigatewayv2_route" "auth_cpf_openapi" {
  api_id             = local.addons.app_api_id
  route_key          = "GET /auth/cpf-openapi.json"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf_openapi" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpfOpenapi"
  action        = "lambda:InvokeFunction"
  function_name = module.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/*/GET/auth/cpf-openapi.json"
}

# Swagger UI da lambda auth-cpf — rota publica que retorna o HTML do Swagger.
# Nao pode usar /auth/{proxy+} no edge (esse apontaria pro ALB); precisa de
# rota propria aqui, direto para a integracao Lambda.
resource "aws_apigatewayv2_route" "auth_cpf_swagger" {
  api_id             = local.addons.app_api_id
  route_key          = "GET /auth/swagger-ui.html"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.auth_cpf.id}"
}

resource "aws_lambda_permission" "app_gateway_invoke_auth_cpf_swagger" {
  statement_id  = "AllowAppApiGatewayInvokeAuthCpfSwagger"
  action        = "lambda:InvokeFunction"
  function_name = module.auth_cpf_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.addons.app_api_execution_arn}/*/GET/auth/swagger-ui.html"
}

# Duplica na borda a verificacao de assinatura/issuer/expiracao do JWT que o
# os-service ja faz. Nao decide por role, so rejeita cedo tokens
# invalidos/ausentes antes de gastar um hop ate o ALB/pod.
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
