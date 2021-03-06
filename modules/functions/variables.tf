variable "votes_sqs_arn" {
  description = "ARN of the votes buffer queue"
}

variable "votes_sqs_id" {
  description = "URL of the voters buffer queue"
}

variable "dead_letter_sqs_arn" {
  description = "ARN of the dead letter queue"
}

variable "dead_letter_sqs_id" {
  description = "URL of the dead letter queue"
}

variable "voters_table_arn" {
  description = "ARN of the voters table"
}

variable "voters_table_name" {
  description = "Name of the voters table"
  default     = "voters"
}

variable "results_table_arn" {
  description = "ARN of the table to election results"
}

variable "results_table_name" {
  description = "Name of the results table"
  default     = "results"
}

variable "kms_arn" {
  description = "ARN of the KMS key"
}

variable "website_domain" {
  description = "Domain of the voting website"
}
