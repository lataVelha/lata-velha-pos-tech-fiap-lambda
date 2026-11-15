output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "subscription_filter_name" {
  value = aws_cloudwatch_log_subscription_filter.apigateway.name
}
