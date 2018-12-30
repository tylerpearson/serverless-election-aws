# More info on DynamoDB encryption here:
# https://docs.aws.amazon.com/kms/latest/developerguide/services-dynamodb.html
# -> When you create an encrypted table, DynamoDB creates a unique AWS managed
# customer master key (CMK) in each region of your AWS account, if one does not
# already exist. This CMK, aws/dynamodb, is known as the service default key.
# Like all CMKs, the service default key never leaves AWS KMS unencrypted.
# The encryption at rest feature does not support the use of customer managed CMKs.

locals {
  gsi_index_name = "state-candidate-index"
}

resource "aws_dynamodb_table" "voters_table" {
  hash_key         = "voter_id"
  name             = "voters"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "voter_id"
    type = "S"
  }

  attribute {
    name = "candidate"
    type = "S"
  }

  attribute {
    name = "state"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  global_secondary_index {
    name            = "${local.gsi_index_name}"
    hash_key        = "state"
    range_key       = "candidate"
    projection_type = "KEYS_ONLY"
    read_capacity   = 5
    write_capacity  = 5
  }

  point_in_time_recovery {
    enabled = true
  }

  # disable when autoscaling
  lifecycle {
    ignore_changes = ["read_capacity", "write_capacity"]
  }
}

resource "aws_dynamodb_table" "results_table" {
  hash_key         = "state"
  range_key        = "candidate"
  name             = "results"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "state"
    type = "S"
  }

  attribute {
    name = "candidate"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = false
  }

  # disable when autoscaling
  lifecycle {
    ignore_changes = ["read_capacity", "write_capacity"]
  }
}

# Read and write autoscaling of tables

module "voters_table_auto_scaling" {
  source     = "./auto_scaling"
  table_name = "${aws_dynamodb_table.voters_table.name}"
}

module "results_table_auto_scaling" {
  source     = "./auto_scaling"
  table_name = "${aws_dynamodb_table.results_table.name}"
}

module "voters_gsi_table_auto_scaling" {
  source       = "./auto_scaling"
  scaling_type = "index"
  table_name   = "${aws_dynamodb_table.voters_table.name}/index/${local.gsi_index_name}"
}
