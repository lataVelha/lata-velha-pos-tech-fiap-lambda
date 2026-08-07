output "auth_cpf_function_name" {
  value = module.auth_cpf_lambda.function_name
}

output "auth_cpf_function_arn" {
  value = module.auth_cpf_lambda.function_arn
}

output "auth_cpf_invoke_arn" {
  description = "invoke_arn da lambda auth-cpf — lido pelo repo infra (addons) para criar a rota POST /auth/cpf no API Gateway do app"
  value       = module.auth_cpf_lambda.invoke_arn
}

output "secret_arn" {
  description = "ARN do secret com a chave JWT e credenciais do banco"
  value       = aws_secretsmanager_secret.auth_cpf.arn
}

output "jwt_authorizer_function_name" {
  value = module.jwt_authorizer_lambda.function_name
}

output "jwt_authorizer_function_arn" {
  value = module.jwt_authorizer_lambda.function_arn
}

output "jwt_authorizer_invoke_arn" {
  description = "invoke_arn da lambda authorizer — lido pelo repo infra (addons) para anexa-la ao API Gateway do app"
  value       = module.jwt_authorizer_lambda.invoke_arn
}
