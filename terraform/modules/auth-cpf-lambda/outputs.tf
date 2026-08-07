output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "ARN usado como integration_uri no API Gateway do app (repo infra)"
  value       = aws_lambda_function.this.invoke_arn
}
