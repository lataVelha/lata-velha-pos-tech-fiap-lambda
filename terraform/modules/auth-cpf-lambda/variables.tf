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

variable "jwt_public_key_pem" {
  description = "Chave publica RSA (PEM) correspondente"
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
  description = "Diretorio com o bundle da lambda ja buildado (npm run build -> dist/)"
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
