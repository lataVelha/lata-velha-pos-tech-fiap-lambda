output "auth_cpf_function_name" {
  value = module.auth_cpf_lambda.function_name
}

output "auth_cpf_function_arn" {
  value = module.auth_cpf_lambda.function_arn
}

output "auth_cpf_invoke_arn" {
  value = module.auth_cpf_lambda.invoke_arn
}

output "jwt_authorizer_function_name" {
  value = module.jwt_authorizer_lambda.function_name
}

output "jwt_authorizer_function_arn" {
  value = module.jwt_authorizer_lambda.function_arn
}

output "jwt_authorizer_invoke_arn" {
  value = module.jwt_authorizer_lambda.invoke_arn
}

output "jwt_authorizer_id" {
  description = "Usado pelo stack edge nas rotas protegidas"
  value       = aws_apigatewayv2_authorizer.jwt.id
}

output "auth_cpf_endpoint" {
  description = "URL do login por CPF (lambda auth-cpf, lendo o RDS do os-service)"
  value       = "${local.addons.app_api_endpoint}auth/cpf"
}
