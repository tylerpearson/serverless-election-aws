resource "aws_sqs_queue" "votes_queue" {
  name                      = "votes-queue"
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 5

  kms_master_key_id                 = "alias/aws/sqs"
  kms_data_key_reuse_period_seconds = "${60 * 5}"
}

output "votes_sqs_arn" {
  value = "${aws_sqs_queue.votes_queue.arn}"
}

output "votes_sqs_id" {
  value = "${aws_sqs_queue.votes_queue.id}"
}
