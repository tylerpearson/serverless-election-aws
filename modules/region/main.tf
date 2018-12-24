data "aws_region" "current" {}

data "aws_route53_zone" "voting_zone" {
  zone_id = "${var.zone_id}"
}

resource "aws_acm_certificate" "cert" {
  domain_name               = "${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"
  subject_alternative_names = ["*.${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  count   = "2"
  zone_id = "${data.aws_route53_zone.voting_zone.id}"
  name    = "${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_name")}"
  type    = "${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_type")}"
  ttl     = "60"
  records = ["${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_value")}"]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.*.fqdn}"]
}

module "lambda_functions" {
  source = "../functions"

  votes_sqs_arn      = "${module.sqs.votes_sqs_arn}"
  votes_sqs_id       = "${module.sqs.votes_sqs_id}"
  voters_table_arn   = "${module.voters_table.voters_table_arn}"
  voters_table_name  = "${module.voters_table.voters_table_name}"
  results_table_arn  = "${module.voters_table.results_table_arn}"
  results_table_name = "${module.voters_table.results_table_name}"
}

module "sqs" {
  source = "../queue"
}

module "voters_table" {
  source = "../database"
}

module "api" {
  source = "../api"

  zone_id                          = "${var.zone_id}"
  cert_arn                         = "${aws_acm_certificate.cert.arn}"
  vote_create_lambda_function_name = "${module.lambda_functions.vote_create_lambda_function_name}"
  results_lambda_function_name     = "${module.lambda_functions.results_lambda_function_name}"
  api_subdomain                    = "${var.api_subdomain}"
}
