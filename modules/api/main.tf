data "aws_lambda_function" "vote_create_lambda" {
  function_name = "${var.vote_create_lambda_function_name}"
}

data "aws_lambda_function" "results_lambda" {
  function_name = "${var.results_lambda_function_name}"
}

locals {
  create_lambda_arn  = "${replace(data.aws_lambda_function.vote_create_lambda.arn, ":$LATEST", "")}"
  results_lambda_arn = "${replace(data.aws_lambda_function.results_lambda.arn, ":$LATEST", "")}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# https://aws.amazon.com/blogs/compute/building-a-multi-region-serverless-application-with-amazon-api-gateway-and-aws-lambda/
resource "aws_api_gateway_rest_api" "api" {
  name        = "voting"
  description = "voting API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "votes"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
}

# Just reuse these existing module to get support for OPTIONS requests with JavaScript
# https://github.com/squidfunk/terraform-aws-api-gateway-enable-cors
module "cors" {
  source  = "github.com/squidfunk/terraform-aws-api-gateway-enable-cors"
  version = "0.1.0"

  api_id          = "${aws_api_gateway_rest_api.api.id}"
  api_resource_id = "${aws_api_gateway_resource.resource.id}"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.resource.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    "aws_api_gateway_integration.integration",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "production"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.resource.id}"
  http_method             = "${aws_api_gateway_method.method.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${local.create_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${data.aws_lambda_function.vote_create_lambda.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}

data "aws_route53_zone" "voting_zone" {
  zone_id = "${var.zone_id}"
}

resource "aws_api_gateway_domain_name" "gw_domain_name" {
  regional_certificate_arn = "${var.cert_arn}"
  domain_name              = "${var.api_subdomain}.${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "app" {
  api_id      = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "${aws_api_gateway_deployment.api.stage_name}"
  domain_name = "${aws_api_gateway_domain_name.gw_domain_name.domain_name}"
}

resource "aws_route53_record" "api" {
  name           = "${aws_api_gateway_domain_name.gw_domain_name.domain_name}"
  type           = "A"
  zone_id        = "${var.zone_id}"
  set_identifier = "${var.api_subdomain}-${data.aws_region.current.name}"

  alias {
    evaluate_target_health = false
    name                   = "${aws_api_gateway_domain_name.gw_domain_name.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.gw_domain_name.regional_zone_id}"
  }

  latency_routing_policy {
    region = "${data.aws_region.current.name}"
  }
}

resource "aws_api_gateway_method" "method_get_all" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.resource.id}"
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_all_integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.resource.id}"
  http_method             = "${aws_api_gateway_method.method_get_all.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${local.results_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "get_all_apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${data.aws_lambda_function.results_lambda.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method_get_all.http_method}${aws_api_gateway_resource.resource.path}"
}
