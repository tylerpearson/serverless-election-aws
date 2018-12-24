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
