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

# --- D1 · Datadog (observabilidade: traces + metricas + logs) ---

variable "region" {
  description = "Regiao da AWS (para compor o ARN das layers Datadog)"
  type        = string
  default     = "us-east-1"
}

variable "dd_api_key" {
  description = "Datadog API key (Extension envia traces/metricas/logs). Via TF_VAR_ — nunca no tfvars"
  type        = string
  sensitive   = true
  default     = ""
}

variable "dd_site" {
  description = "Site Datadog de destino (tem que bater com o site do Agent: us5)"
  type        = string
  default     = "us5.datadoghq.com"
}

variable "dd_env" {
  description = "Tag 'env' do Datadog (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "dd_version" {
  description = "Tag 'version' do Datadog (correlacao deploy↔trace). Vazio = sem tag"
  type        = string
  default     = ""
}

variable "datadog_extension_layer_version" {
  description = "Versao da layer Datadog-Extension (atualizar conforme CHANGELOG do datadog-lambda-py)"
  type        = number
  default     = 97
}

variable "datadog_python_layer_version" {
  description = "Versao da layer Datadog-Python312 (atualizar conforme CHANGELOG do datadog-lambda-py)"
  type        = number
  default     = 125
}
