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
    # ignore_changes = ["read_capacity", "write_capacity"]
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity = 250
  min_capacity = 5
  resource_id  = "table/${aws_dynamodb_table.voters_table.name}"

  # role_arn           = "${data.aws_iam_role.autoscale_service_linked_role.arn}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = "${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  scalable_dimension = "${aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension}"
  service_namespace  = "${aws_appautoscaling_target.dynamodb_table_read_target.service_namespace}"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }

    target_value = 90
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  max_capacity = 1000
  min_capacity = 5
  resource_id  = "table/${aws_dynamodb_table.voters_table.name}"

  # role_arn           = "${data.aws_iam_role.autoscale_service_linked_role.arn}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = "${aws_appautoscaling_target.dynamodb_table_write_target.resource_id}"
  scalable_dimension = "${aws_appautoscaling_target.dynamodb_table_write_target.scalable_dimension}"
  service_namespace  = "${aws_appautoscaling_target.dynamodb_table_write_target.service_namespace}"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }

    target_value = 90
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
    # ignore_changes = ["read_capacity", "write_capacity"]
  }
}

# Outputs

output "voters_table_arn" {
  value = "${aws_dynamodb_table.voters_table.arn}"
}

output "voters_table_name" {
  value = "${aws_dynamodb_table.voters_table.id}"
}

output "results_table_arn" {
  value = "${aws_dynamodb_table.results_table.arn}"
}

output "results_table_name" {
  value = "${aws_dynamodb_table.results_table.id}"
}
