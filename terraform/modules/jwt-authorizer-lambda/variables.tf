variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
}

variable "secret_arn" {
  description = "ARN do secret no Secrets Manager com a chave publica RSA (JWT) — mesmo secret usado pela lambda auth-cpf"
  type        = string
}

variable "dist_dir" {
  description = "Diretorio com o bundle ja buildado (npm run build -> dist/authorizer.js)"
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
