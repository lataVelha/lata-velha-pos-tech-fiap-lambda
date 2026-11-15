variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC (para o security group da lambda)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde a lambda roda — precisa ser a mesma VPC do RDS"
  type        = list(string)
}

variable "jwt_private_key_pem" {
  description = "Chave privada RSA (PEM) — mesma usada pelo app para assinar/validar tokens"
  type        = string
  sensitive   = true
}

variable "jwt_issuer" {
  description = "Claim 'iss' do token"
  type        = string
}

variable "jwt_expires_in" {
  description = "Validade do token em segundos"
  type        = number
}

variable "db_host" {
  description = "Host do RDS"
  type        = string
}

variable "db_port" {
  description = "Porta do RDS"
  type        = number
}

variable "db_name" {
  description = "Nome do banco"
  type        = string
}

variable "db_user" {
  description = "Usuario do banco"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha do banco"
  type        = string
  sensitive   = true
}

variable "dist_dir" {
  description = "Diretorio com o build ja gerado (./build.sh -> build/<nome>/)"
  type        = string
}

variable "timeout" {
  description = "Timeout da lambda em segundos"
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Memoria alocada para a lambda (MB)"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "Retencao dos logs da lambda no CloudWatch"
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
