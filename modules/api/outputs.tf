output "vote_enqueuer_lambda_invocation_domain" {
  value = "${aws_api_gateway_deployment.api.invoke_url}"
}

output "vote_enqueuer_lambda_invocation_url" {
  value = "${aws_api_gateway_deployment.api.invoke_url}/${aws_api_gateway_resource.resource.path_part}"
}

output "api_resource" {
  value = "${aws_api_gateway_resource.resource.path}"
}
