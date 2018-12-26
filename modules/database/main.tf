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
    name            = "state-candidate-index"
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

# Read and write =autoscaling of tables

module "voters_table_auto_scaling" {
  source     = "./auto_scaling"
  table_name = "${aws_dynamodb_table.voters_table.name}"
}

module "results_table_auto_scaling" {
  source     = "./auto_scaling"
  table_name = "${aws_dynamodb_table.results_table.name}"
}
