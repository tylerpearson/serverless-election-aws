data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_lambda_function" "vote_enqueuer_lambda" {
  function_name = "${var.vote_enqueuer_lambda_function_name}"
}

data "aws_lambda_function" "results_lambda" {
  function_name = "${var.results_lambda_function_name}"
}

data "aws_lambda_function" "health_check_lambda" {
  function_name = "${var.health_check_lambda_function_name}"
}

locals {
  vote_enqueuer_lambda_arn = "${replace(data.aws_lambda_function.vote_enqueuer_lambda.arn, ":$LATEST", "")}"
  results_lambda_arn       = "${replace(data.aws_lambda_function.results_lambda.arn, ":$LATEST", "")}"
  health_check_lambda_arn  = "${replace(data.aws_lambda_function.health_check_lambda.arn, ":$LATEST", "")}"
  stage_name               = "production"
}

resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = "${aws_iam_role.cloudwatch.arn}"
}

resource "aws_iam_role" "cloudwatch" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch" {
  role = "${aws_iam_role.cloudwatch.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

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
  allow_origin    = "https://${replace(data.aws_route53_zone.voting_zone.name, "/[.]$/", "")}"
  allow_methods   = ["OPTIONS", "HEAD", "GET", "POST"]
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.resource.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_settings" "settings" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "${local.stage_name}"
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }

  depends_on = ["aws_api_gateway_stage.production"]
}

resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    "aws_api_gateway_integration.integration",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = ""
}

resource "aws_api_gateway_stage" "production" {
  stage_name           = "${local.stage_name}"
  rest_api_id          = "${aws_api_gateway_rest_api.api.id}"
  deployment_id        = "${aws_api_gateway_deployment.api.id}"
  xray_tracing_enabled = true
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.resource.id}"
  http_method             = "${aws_api_gateway_method.method.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${local.vote_enqueuer_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${data.aws_lambda_function.vote_enqueuer_lambda.function_name}"
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
  stage_name  = "${aws_api_gateway_stage.production.stage_name}"
  domain_name = "${aws_api_gateway_domain_name.gw_domain_name.domain_name}"
}

resource "aws_route53_health_check" "health_check" {
  reference_name    = "${data.aws_region.current.name} API Gateway check"
  fqdn              = "${replace(replace(replace(aws_api_gateway_deployment.api.invoke_url, "https://", ""), "/${aws_api_gateway_stage.production.stage_name}/", ""), "/", "")}"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/${aws_api_gateway_stage.production.stage_name}${aws_api_gateway_resource.health_check_resource.path}"
  failure_threshold = "2"
  request_interval  = "30"
  measure_latency   = true
  regions           = ["us-east-1", "us-west-1", "us-west-2"]                                                                                                             # restrict the regions this checks from                                                                                            # us-east-2 isn't a supported region for health check in the US
}

resource "aws_route53_record" "api" {
  name           = "${aws_api_gateway_domain_name.gw_domain_name.domain_name}"
  type           = "A"
  zone_id        = "${var.zone_id}"
  set_identifier = "${var.api_subdomain}-${data.aws_region.current.name}"

  # https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-values-latency-alias.html#rrsets-values-latency-alias-evaluate-target-health
  alias {
    evaluate_target_health = true
    name                   = "${aws_api_gateway_domain_name.gw_domain_name.regional_domain_name}"
    zone_id                = "${aws_api_gateway_domain_name.gw_domain_name.regional_zone_id}"
  }

  health_check_id = "${aws_route53_health_check.health_check.id}"

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

resource "aws_api_gateway_resource" "health_check_resource" {
  path_part   = "health"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
}

resource "aws_api_gateway_method" "method_health_check" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.health_check_resource.id}"
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health_check_integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.health_check_resource.id}"
  http_method             = "${aws_api_gateway_method.method_health_check.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${local.health_check_lambda_arn}/invocations"
}

resource "aws_lambda_permission" "health_check_apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${data.aws_lambda_function.health_check_lambda.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method_health_check.http_method}${aws_api_gateway_resource.health_check_resource.path}"
}
