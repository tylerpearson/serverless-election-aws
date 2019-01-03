output "votes_sqs_arn" {
  value = "${aws_sqs_queue.votes_queue.arn}"
}

output "votes_sqs_id" {
  value = "${aws_sqs_queue.votes_queue.id}"
}

output "dead_letter_sqs_arn" {
  value = "${aws_sqs_queue.dead_letter_queue.arn}"
}

output "dead_letter_sqs_id" {
  value = "${aws_sqs_queue.dead_letter_queue.id}"
}
