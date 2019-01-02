output "invocation_url" {
  value = "${module.api.vote_enqueuer_lambda_invocation_url}"
}

output "api_resource" {
  value = "${module.api.api_resource}"
}

output "cert_arn" {
  value = "${aws_acm_certificate.cert.arn}"
}

output "results_table_name" {
  value = "${module.database.results_table_name}"
}

output "voters_table_name" {
  value = "${module.database.voters_table_name}"
}
