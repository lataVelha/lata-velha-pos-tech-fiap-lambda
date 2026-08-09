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
