output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "ARN usado como authorizer_uri no aws_apigatewayv2_authorizer"
  value       = aws_lambda_function.this.invoke_arn
}
