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

variable "secret_arn" {
  description = "ARN do secret no Secrets Manager com a chave JWT e as credenciais do banco"
  type        = string
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
