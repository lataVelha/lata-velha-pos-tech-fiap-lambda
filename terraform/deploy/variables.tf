variable "region" {
  description = "Regiao da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "lata-velha"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "state_bucket" {
  description = "Bucket S3 com o estado do bootstrap (VPC) e do infra-db (RDS) — e onde este state tambem sera gravado"
  type        = string
}

variable "bootstrap_state_key" {
  description = "Chave do state do bootstrap (repo infra) dentro do state_bucket, de onde vem vpc_id/subnets"
  type        = string
  default     = "lata-velha/bootstrap/terraform.tfstate"
}

variable "infra_db_state_key" {
  description = "Chave do state do infra-db dentro do state_bucket, de onde vem o endpoint/credenciais do RDS"
  type        = string
  default     = "lata-velha/infra-db/terraform.tfstate"
}

variable "addons_state_key" {
  description = "Chave do state do repo infra (addons) dentro do state_bucket, de onde vem o api_id/execution_arn do API Gateway"
  type        = string
  default     = "lata-velha/infra-addons/terraform.tfstate"
}


# --- JWT ---
# A lambda precisa assinar tokens com a MESMA chave privada RSA que o app
# usa para validar (classpath:app.key / app.pub, ver JwtConfig.java).
# Default = conteudo atual de app.key/app.pub, so para nao precisar exportar
# TF_VAR_* toda vez rodando local. Em CI, os secrets TF_JWT_PRIVATE_KEY_PEM/
# TF_JWT_PUBLIC_KEY_PEM sempre sobrescrevem este default. Se algum dia
# rotacionar as chaves no app, atualize os defaults abaixo tambem.
variable "jwt_private_key_pem" {
  description = "Chave privada RSA (PEM, PKCS8) — mesma usada pelo app em app.key"
  type        = string
  sensitive   = true
  default     = <<-EOT
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDOJ9iY+rXY4jaY
    QYjUZ8wWE/DtpnlWfcHyoBVzx7bwE45vfb2ABnVUE186MZ7705Owa62WbVZgFCPs
    7RlO4SXC8f50Q7pDx3I16TXIGJVNP86T9oPNUY4d1LS/S0xV9ADyPGYc1XPzTthW
    YTfq8I2q/SebHmNAAwY0jvs3+rngs0cHCFYE6y84//JAFFqmk40KiUsrkYGjEe0g
    oDYBPq1zwHWk9b0ZJ8urjEeaJjbluBoxoEzA8soUzD6zLPBbqyf3vHOQfj/OHrL4
    L+idffNDDdM02GcqDUtQYIaPZogg6PfFuvZVgg3HVT5MhbZL6A9XSAsDFxGI0eqQ
    I/8+xIPBAgMBAAECggEAIu12UYjciWfeJxKnW5FQbwcm4SS81w4Mb452w/x4vpkZ
    n0MW+ZtegoWbszDYBkN0+MVtjhhtM28GHSyYhpg3vR0h5tHYu4YNkBu4bHPZy9I9
    Li1sbDtekChLDUP1JXTnOiNIi6cQc48OsSfcgPYLkoY8kRfnad95TCtTXcshdfOr
    qBpJF+C4kwaU5zn11HT0Ljfmjvi2huyzK9NSd/w0xunfHg7GYjORqGkwq3VitrzI
    Nh4Si1VT0n8shCG5bzLxrdEdHtWAQWFCguRn2iSVk1vd4oFLmp/SPge8sSNfTJ+C
    OBGX2oLi+36SRJ8Z2+dXpNRscGqD2daL1HcG9P9hVwKBgQD8yertdTu+FyX63ZjX
    Ns3jkev8t/HYdB/ka5ONnFfreuauUCYFh5vjZwxbA14GacsyQNhEy/3u/+IJVrIO
    pPSkUi7NFDXzrI7QwAn5eT3nRQrncqY34eeTCgjO4vL8Kj5hn5MYgnt1C9DmBmd2
    UXSFntvRLOOlVnTd0K+iQaokEwKBgQDQxkZuhHYgVsujiQMIuVwTJ6npXdFzLAkB
    xFACLYdklPJPLXsOu0ReUE7KWQOldG6wMadhXpEFRyFnWcblJpsC8XgkBoWreygQ
    4XjKgTxUb1IIAT/dpKMrYl4QcPo6hOEAeBPJZPyIbFqJ4rFtUUNleQSMoj7l9S/y
    4/psRiurWwKBgDIOBW/Jo+/LA6E+GdKbrn8eWN0syz2yGNKRHqGO0LX3GxBvHGhB
    5vNLZ13qN8cLUcn8nxZYUkrt7iMtQIq3zR1wjIXdN6WtiIX7UL5ObJyLxlH4GMO9
    /q3V8dKNi9G0x69q+qSCydFuaonxwLDkBi+jOiGcQuNtUCzP8sctO3RzAoGBAJCG
    MYugNwX8D8yNtIP9jTfVZVIfmDbabQHEHH7ldayzT2pwWZfBG3sOrPx20odfKqDe
    Priw9kNpEj6xb3aCWxyWfEy0FyS2hO3qp+vHuzPYPDk+ZC/TIQGPfv5yt0Z7Zick
    +M2aExd9qs95FspOTxGXzQZt6ozWRvMlzt3VVbWxAoGBALRvbzHICjec9b4qKBWC
    Gc/bcJJr3jqjTbRHUA0HQmhsDfsCwWcX+w+7rdVQA9uUFfU1HoxvG71lXQ1JOV9g
    PnyCMvfyNUrn/jYpfrRy+X3h4uJANLeJwo+uZ+IqHVxWrNd0uVJqLaU+dX4lNkhW
    8MpIMnkFQA90HFj0WX00pwiF
    -----END PRIVATE KEY-----
  EOT
}

variable "jwt_public_key_pem" {
  description = "Chave publica RSA (PEM) correspondente — mesma usada pelo app em app.pub. So a jwt-authorizer usa (verifica assinatura); a auth-cpf so assina, com a privada"
  type        = string
  sensitive   = true
  default     = <<-EOT
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzifYmPq12OI2mEGI1GfM
    FhPw7aZ5Vn3B8qAVc8e28BOOb329gAZ1VBNfOjGe+9OTsGutlm1WYBQj7O0ZTuEl
    wvH+dEO6Q8dyNek1yBiVTT/Ok/aDzVGOHdS0v0tMVfQA8jxmHNVz807YVmE36vCN
    qv0nmx5jQAMGNI77N/q54LNHBwhWBOsvOP/yQBRappONColLK5GBoxHtIKA2AT6t
    c8B1pPW9GSfLq4xHmiY25bgaMaBMwPLKFMw+syzwW6sn97xzkH4/zh6y+C/onX3z
    Qw3TNNhnKg1LUGCGj2aIIOj3xbr2VYINx1U+TIW2S+gPV0gLAxcRiNHqkCP/PsSD
    wQIDAQAB
    -----END PUBLIC KEY-----
  EOT
}

variable "jwt_issuer" {
  description = "Claim 'iss' do token — precisa bater com JWT_ISSUER do app"
  type        = string
  default     = "lata-velha"
}

variable "jwt_expires_in" {
  description = "Validade do token em segundos — precisa bater com JWT_EXPIRES_IN do app"
  type        = number
  default     = 3600
}

# --- Lambda ---
variable "lambda_timeout" {
  description = "Timeout da lambda em segundos"
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Memoria alocada para a lambda (MB)"
  type        = number
  default     = 256
}
