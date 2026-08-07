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

locals {
  bootstrap = data.terraform_remote_state.bootstrap.outputs
  infra_db  = data.terraform_remote_state.infra_db.outputs

  # rds_endpoint vem como "host:porta"
  db_host = split(":", local.infra_db.rds_endpoint)[0]
  db_port = tonumber(split(":", local.infra_db.rds_endpoint)[1])
}

# Fonte unica da chave JWT (RS256) e das credenciais do banco para a lambda.
# A chave privada aqui PRECISA ser a mesma configurada em app.key/app.pub no
# app (JwtConfig.java) — do contrario o JwtDecoder do app rejeita os tokens
# emitidos por esta function.
resource "aws_secretsmanager_secret" "auth_cpf" {
  name        = "${var.project_name}/auth-cpf-lambda"
  description = "Chave JWT (RS256, compartilhada com o app) + credenciais do RDS usadas pela lambda de login por CPF"
}

resource "aws_secretsmanager_secret_version" "auth_cpf" {
  secret_id = aws_secretsmanager_secret.auth_cpf.id
  secret_string = jsonencode({
    jwtPrivateKey = var.jwt_private_key_pem
    jwtPublicKey  = var.jwt_public_key_pem
    jwtIssuer     = var.jwt_issuer
    jwtExpiresIn  = var.jwt_expires_in
    dbHost        = local.db_host
    dbPort        = local.db_port
    dbName        = local.infra_db.db_name
    dbUser        = local.infra_db.db_username
    dbPassword    = local.infra_db.db_password
  })
}

module "auth_cpf_lambda" {
  source = "../modules/auth-cpf-lambda"

  project_name       = var.project_name
  vpc_id             = local.bootstrap.vpc_id
  private_subnet_ids = local.bootstrap.private_subnet_ids
  secret_arn         = aws_secretsmanager_secret.auth_cpf.arn
  dist_dir           = "${path.module}/../../dist"
  timeout            = var.lambda_timeout
  memory_size        = var.lambda_memory_size
}

# --------------------------------------------------------------------------
# Lambda authorizer do API Gateway do app (repo infra). Duplica, na borda,
# a mesma verificacao de assinatura/issuer/expiracao que o JwtDecoder do app
# ja faz — nao decide autorizacao por role, isso continua 100% no
# SecurityConfig do app. Le o MESMO secret da lambda auth-cpf (usa so o
# campo jwtPublicKey).
#
# So a FUNCAO e criada aqui — quem anexa ela ao API Gateway (aws_apigatewayv2_authorizer,
# aws_lambda_permission, rotas protegidas) e o modulo app-gateway no repo
# infra, que le o ARN dela (outputs.tf) via terraform_remote_state. Por isso
# o pipeline roda infra bootstrap -> infra-db -> lambda -> infra addons ->
# app: addons precisa que esta funcao ja exista.
# --------------------------------------------------------------------------

module "jwt_authorizer_lambda" {
  source = "../modules/jwt-authorizer-lambda"

  project_name = var.project_name
  secret_arn   = aws_secretsmanager_secret.auth_cpf.arn
  dist_dir     = "${path.module}/../../dist"
}
