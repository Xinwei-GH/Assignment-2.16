output "invoke_url" {
  value = trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")
}


output "api_invoke_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
  description = "The invoke URL for the HTTP API Gateway."
}