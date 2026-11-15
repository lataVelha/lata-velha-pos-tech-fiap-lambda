variable "project_name" {
  description = "Prefixo dos recursos"
  type        = string
}

variable "dist_dir" {
  description = "Diretório com o build já gerado (./build.sh -> build/logs-forwarder/)"
  type        = string
}

variable "log_group_name" {
  description = "Log group do API Gateway que será assinado"
  type        = string
}

variable "log_group_arn" {
  description = "ARN do log group do API Gateway"
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

variable "dd_env" {
  description = "Ambiente do Datadog (DD_ENV)"
  type        = string
  default     = "prod"
}

variable "service_version" {
  description = "Versão publicada (DD_VERSION)"
  type        = string
  default     = "dev"
}

variable "timeout" {
  description = "Timeout da Lambda em segundos"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memória da Lambda em MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "Retenção dos logs da própria Lambda no CloudWatch"
  type        = number
  default     = 14
}
