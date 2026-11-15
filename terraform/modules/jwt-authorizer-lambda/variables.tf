variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
}

variable "jwt_public_key_pem" {
  description = "Chave publica RSA (PEM) — mesma usada pela lambda auth-cpf, so pra verificar assinatura"
  type        = string
  sensitive   = true
}

variable "jwt_issuer" {
  description = "Claim 'iss' esperado no token"
  type        = string
}

variable "dist_dir" {
  description = "Diretorio com o build ja gerado (./build.sh -> build/<nome>/)"
  type        = string
}

variable "timeout" {
  description = "Timeout da lambda em segundos"
  type        = number
  default     = 5
}

variable "memory_size" {
  description = "Memoria alocada para a lambda (MB)"
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "Retencao dos logs no CloudWatch"
  type        = number
  default     = 14
}

variable "aws_region" {
  description = "Região AWS — usada para montar o ARN da layer da Datadog"
  type        = string
}

variable "environment" {
  description = "Ambiente do Datadog (DD_ENV)"
  type        = string
}

variable "service_version" {
  description = "Versão publicada (DD_VERSION)"
  type        = string
}

variable "dd_api_key" {
  description = "API key do Datadog (sensitive)"
  type        = string
  sensitive   = true
}

variable "dd_site" {
  description = "Site do Datadog"
  type        = string
  default     = "us5.datadoghq.com"
}

variable "dd_extension_version" {
  description = "Versão da layer Datadog Lambda Extension"
  type        = string
  default     = "103"
}
