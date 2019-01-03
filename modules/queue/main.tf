resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = "dead-letter-queue"
  message_retention_seconds = 1209600
  kms_master_key_id         = "${var.kms_arn}"
}

resource "aws_sqs_queue" "votes_queue" {
  name                              = "votes-queue"
  message_retention_seconds         = 259200
  receive_wait_time_seconds         = 5
  kms_master_key_id                 = "${var.kms_arn}"
  kms_data_key_reuse_period_seconds = "${60 * 5}"
  redrive_policy                    = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.dead_letter_queue.arn}\",\"maxReceiveCount\":2}"
}
