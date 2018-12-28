output "invocation_url" {
  value = "${module.api.vote_enqueuer_lambda_invocation_url}"
}

output "api_resource" {
  value = "${module.api.api_resource}"
}
