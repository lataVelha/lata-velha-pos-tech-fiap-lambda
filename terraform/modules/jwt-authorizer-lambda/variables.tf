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

# --- D1 · Datadog — mesmas vars do modulo auth-cpf-lambda ---

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
