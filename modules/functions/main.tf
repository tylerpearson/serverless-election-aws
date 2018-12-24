data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

## Vote Create - Listens to incoming vote and puts to SQS queue for processing

resource "aws_cloudwatch_log_group" "create_lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.vote_create_lambda.function_name}"
}

data "archive_file" "vote_create_files" {
  type        = "zip"
  source_dir  = "${path.module}/vote_create/index"
  output_path = "${path.module}/vote_create/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "vote_create_lambda" {
  filename         = "${path.module}/vote_create/files/${data.aws_region.current.name}/index.zip"
  function_name    = "vote_create_function"
  role             = "${aws_iam_role.vote_create_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  timeout          = "30"
  source_code_hash = "${data.archive_file.vote_create_files.output_base64sha256}"

  environment {
    variables = {
      VOTES_QUEUE_URL          = "${var.votes_sqs_id}"
      VOTERS_DYNAMO_TABLE_NAME = "${var.voters_table_name}"
    }
  }
}

data "aws_iam_policy_document" "vote_create_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.create_lambda_log_group.arn}",
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

resource "aws_iam_role" "vote_create_lambda" {
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

resource "aws_iam_role_policy" "vote_create_role_policy_lambda" {
  name   = "${aws_iam_role.vote_create_lambda.name}-policy"
  role   = "${aws_iam_role.vote_create_lambda.id}"
  policy = "${data.aws_iam_policy_document.vote_create_lambda_policy.json}"
}

## Vote Save - Listens to SQS and saves vote

resource "aws_cloudwatch_log_group" "save_lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.vote_save_lambda.function_name}"

  # kms_key_id = "alias/aws/cloudwatch"
}

data "archive_file" "vote_save_files" {
  type        = "zip"
  source_dir  = "${path.module}/vote_save/index"
  output_path = "${path.module}/vote_save/files/${data.aws_region.current.name}/index.zip"
}

resource "aws_lambda_function" "vote_save_lambda" {
  filename         = "${path.module}/vote_save/files/${data.aws_region.current.name}/index.zip"
  function_name    = "vote_save_function"
  role             = "${aws_iam_role.vote_save_lambda.arn}"
  runtime          = "ruby2.5"
  handler          = "function.handler"
  source_code_hash = "${data.archive_file.vote_save_files.output_base64sha256}"

  environment {
    variables = {
      VOTERS_DYNAMO_TABLE_NAME  = "${var.voters_table_name}"
      RESULTS_DYNAMO_TABLE_NAME = "${var.results_table_name}"
    }
  }
}

data "aws_iam_policy_document" "vote_save_lambda_policy" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      "${aws_cloudwatch_log_group.save_lambda_log_group.arn}",
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

resource "aws_iam_role" "vote_save_lambda" {
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

resource "aws_iam_role_policy" "vote_save_role_policy_lambda" {
  name   = "${aws_iam_role.vote_save_lambda.name}-policy"
  role   = "${aws_iam_role.vote_save_lambda.id}"
  policy = "${data.aws_iam_policy_document.vote_save_lambda_policy.json}"
}

resource "aws_lambda_event_source_mapping" "lambda_sqs_trigger" {
  event_source_arn = "${var.votes_sqs_arn}"
  function_name    = "${aws_lambda_function.vote_save_lambda.arn}"
}

## Results - shows election results

resource "aws_cloudwatch_log_group" "results_lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.results_lambda.function_name}"

  # kms_key_id = "alias/aws/cloudwatch"
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
  timeout          = "300"

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
