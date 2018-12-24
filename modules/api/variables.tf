variable "vote_create_lambda_function_name" {
  description = "Name of the function that sends the incoming votes to the queue"
}

variable "results_lambda_function_name" {
  description = "Name of the function that shows the election results"
}

variable "zone_id" {
  description = "Id of the Route 53 zone"
}

variable "cert_arn" {
  description = "ARN of the region-specific SSL certificate"
}

variable "api_subdomain" {
  description = "Subdomain that the API gateway is available on"
  default     = "api"
}
