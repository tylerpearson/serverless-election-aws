output "vote_enqueuer_lambda_arn" {
  value = "${aws_lambda_function.vote_enqueuer_lambda.arn}"
}

output "vote_enqueuer_lambda_function_name" {
  value = "${aws_lambda_function.vote_enqueuer_lambda.function_name}"
}

output "results_lambda_arn" {
  value = "${aws_lambda_function.results_lambda.arn}"
}

output "results_lambda_function_name" {
  value = "${aws_lambda_function.results_lambda.function_name}"
}

output "health_check_lambda_arn" {
  value = "${aws_lambda_function.health_check_lambda.arn}"
}

output "health_check_lambda_function_name" {
  value = "${aws_lambda_function.health_check_lambda.function_name}"
}
