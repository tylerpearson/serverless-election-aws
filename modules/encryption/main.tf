data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  statement {
    effect = "Allow"

    // https://docs.aws.amazon.com/IAM/latest/UserGuide/list_kms.html
    actions = [
      "kms:*",
    ]

    principals = {
      type = "AWS"

      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      ]
    }

    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    // https://docs.aws.amazon.com/IAM/latest/UserGuide/list_kms.html
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    principals = {
      type = "Service"

      identifiers = [
        "logs.${data.aws_region.current.name}.amazonaws.com",
      ]
    }

    resources = [
      "*",
    ]
  }
}

resource "aws_kms_key" "kms_key" {
  is_enabled          = true
  enable_key_rotation = true
  policy              = "${data.aws_iam_policy_document.kms.json}"
}

resource "aws_kms_alias" "alias" {
  name          = "alias/${data.aws_region.current.name}/election"
  target_key_id = "${aws_kms_key.kms_key.id}"
}

output "kms_key_arn" {
  value = "${aws_kms_key.kms_key.arn}"
}
