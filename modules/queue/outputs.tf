output "votes_sqs_arn" {
  value = "${aws_sqs_queue.votes_queue.arn}"
}

output "votes_sqs_id" {
  value = "${aws_sqs_queue.votes_queue.id}"
}
