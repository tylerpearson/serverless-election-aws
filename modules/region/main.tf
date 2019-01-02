data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_route53_zone" "voting_zone" {
  zone_id = "${var.zone_id}"
}

resource "aws_acm_certificate" "cert" {
  domain_name               = "${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"
  subject_alternative_names = ["${var.api_subdomain}.${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"]
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
  voters_table_arn   = "${module.database.voters_table_arn}"
  voters_table_name  = "${module.database.voters_table_name}"
  results_table_arn  = "${module.database.results_table_arn}"
  results_table_name = "${module.database.results_table_name}"
  kms_arn            = "${module.encryption.kms_key_arn}"
  website_domain     = "${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"
}

module "encryption" {
  source = "../encryption"
}

module "sqs" {
  source  = "../queue"
  kms_arn = "${module.encryption.kms_key_arn}"
}

module "database" {
  source = "../database" # TODO: Change this name to "database"
}

module "api" {
  source = "../api"

  zone_id                            = "${var.zone_id}"
  cert_arn                           = "${aws_acm_certificate.cert.arn}"
  vote_enqueuer_lambda_function_name = "${module.lambda_functions.vote_enqueuer_lambda_function_name}"
  results_lambda_function_name       = "${module.lambda_functions.results_lambda_function_name}"
  health_check_lambda_function_name  = "${module.lambda_functions.health_check_lambda_function_name}"
  api_subdomain                      = "${var.api_subdomain}"
}
