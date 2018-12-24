output "invocation_url" {
  value = "${module.api.vote_create_lambda_invocation_url}"
}

output "api_resource" {
  value = "${module.api.api_resource}"
}
