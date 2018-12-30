data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

## Vote Enqueuer - Listens to incoming vote and puts to SQS queue for processing

resource "aws_cloudwatch_log_group" "vote_enqueuer_lambda_log_group" {
  name       = "/aws/lambda/${aws_lambda_function.vote_enqueuer_lambda.function_name}"
  kms_key_id = "${var.kms_arn}"
}

data "archive_file" "vote_enqueuer_files" {
  type        = "zip"
  source_dir  = "${path.module}/vote_enqueuer/index"
  output_path = "${path.module}/vote_enqueuer/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "vote_enqueuer_lambda" {
  filename         = "${path.module}/vote_enqueuer/files/${data.aws_region.current.name}/index.zip"
  function_name    = "vote_enqueuer_function"
  role             = "${aws_iam_role.vote_enqueuer_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  timeout          = "30"
  source_code_hash = "${data.archive_file.vote_enqueuer_files.output_base64sha256}"
  kms_key_arn      = "${var.kms_arn}"

  environment {
    variables = {
      VOTES_QUEUE_URL          = "${var.votes_sqs_id}"
      VOTERS_DYNAMO_TABLE_NAME = "${var.voters_table_name}"
    }
  }
}

data "aws_iam_policy_document" "vote_enqueuer_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.vote_enqueuer_lambda_log_group.arn}",
    ]
  }

  statement {
    actions = [
      "sqs:SendMessage",
    ]

    resources = [
      "${var.votes_sqs_arn}",
    ]
  }

  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
    ]

    resources = [
      "${var.voters_table_arn}",
    ]
  }
}

resource "aws_iam_role" "vote_enqueuer_lambda" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vote_enqueuer_role_policy_lambda" {
  name   = "${aws_iam_role.vote_enqueuer_lambda.name}-policy"
  role   = "${aws_iam_role.vote_enqueuer_lambda.id}"
  policy = "${data.aws_iam_policy_document.vote_enqueuer_lambda_policy.json}"
}

## Vote Processor - Listens to SQS and saves vote

resource "aws_cloudwatch_log_group" "vote_processor_lambda_log_group" {
  name       = "/aws/lambda/${aws_lambda_function.vote_processor_lambda.function_name}"
  kms_key_id = "${var.kms_arn}"
}

data "archive_file" "vote_processor_files" {
  type        = "zip"
  source_dir  = "${path.module}/vote_processor/index"
  output_path = "${path.module}/vote_processor/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "vote_processor_lambda" {
  filename         = "${path.module}/vote_processor/files/${data.aws_region.current.name}/index.zip"
  function_name    = "vote_processor_function"
  role             = "${aws_iam_role.vote_processor_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  source_code_hash = "${data.archive_file.vote_processor_files.output_base64sha256}"
  kms_key_arn      = "${var.kms_arn}"

  environment {
    variables = {
      VOTERS_DYNAMO_TABLE_NAME  = "${var.voters_table_name}"
      RESULTS_DYNAMO_TABLE_NAME = "${var.results_table_name}"
    }
  }
}

data "aws_iam_policy_document" "vote_processor_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.vote_processor_lambda_log_group.arn}",
    ]
  }

  statement {
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [
      "${var.votes_sqs_arn}",
    ]
  }

  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:UpdateItem",
    ]

    resources = [
      "${var.voters_table_arn}",
      "${var.results_table_arn}",
    ]
  }
}

resource "aws_iam_role" "vote_processor_lambda" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vote_processor_role_policy_lambda" {
  name   = "${aws_iam_role.vote_processor_lambda.name}-policy"
  role   = "${aws_iam_role.vote_processor_lambda.id}"
  policy = "${data.aws_iam_policy_document.vote_processor_lambda_policy.json}"
}

resource "aws_lambda_event_source_mapping" "lambda_sqs_trigger" {
  event_source_arn = "${var.votes_sqs_arn}"
  function_name    = "${aws_lambda_function.vote_processor_lambda.arn}"
}

## Results - shows election results

resource "aws_cloudwatch_log_group" "results_lambda_log_group" {
  name       = "/aws/lambda/${aws_lambda_function.results_lambda.function_name}"
  kms_key_id = "${var.kms_arn}"
}

data "archive_file" "results_files" {
  type        = "zip"
  source_dir  = "${path.module}/get_results/index"
  output_path = "${path.module}/get_results/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "results_lambda" {
  filename         = "${path.module}/get_results/files/${data.aws_region.current.name}/index.zip"
  function_name    = "results_function"
  role             = "${aws_iam_role.results_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  source_code_hash = "${data.archive_file.results_files.output_base64sha256}"
  timeout          = "30"

  environment {
    variables = {
      RESULTS_DYNAMO_TABLE_NAME = "${var.results_table_name}"
    }
  }
}

data "aws_iam_policy_document" "results_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.results_lambda_log_group.arn}",
    ]
  }

  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Scan",
    ]

    resources = [
      "${var.results_table_arn}",
    ]
  }
}

resource "aws_iam_role" "results_lambda" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vote_results_role_policy_lambda" {
  name   = "${aws_iam_role.results_lambda.name}-policy"
  role   = "${aws_iam_role.results_lambda.id}"
  policy = "${data.aws_iam_policy_document.results_lambda_policy.json}"
}

# Health Check

resource "aws_cloudwatch_log_group" "health_check_lambda_log_group" {
  name       = "/aws/lambda/${aws_lambda_function.health_check_lambda.function_name}"
  kms_key_id = "${var.kms_arn}"
}

data "archive_file" "health_check_files" {
  type        = "zip"
  source_dir  = "${path.module}/health_check/index"
  output_path = "${path.module}/health_check/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "health_check_lambda" {
  filename         = "${path.module}/health_check/files/${data.aws_region.current.name}/index.zip"
  function_name    = "health_check_function"
  role             = "${aws_iam_role.health_check_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  source_code_hash = "${data.archive_file.health_check_files.output_base64sha256}"
  timeout          = "30"
}

data "aws_iam_policy_document" "health_check_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.health_check_lambda_log_group.arn}",
    ]
  }
}

resource "aws_iam_role" "health_check_lambda" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "health_check_role_policy_lambda" {
  name   = "${aws_iam_role.health_check_lambda.name}-policy"
  role   = "${aws_iam_role.health_check_lambda.id}"
  policy = "${data.aws_iam_policy_document.health_check_lambda_policy.json}"
}
