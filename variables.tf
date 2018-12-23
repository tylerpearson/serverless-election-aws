variable "api_subdomain" {
  description = "The subdomain that the api will be available on"
  default     = "api"
}

variable "domain_name" {
  description = "Domain name that the project will run on"
}

variable "project_subdomain" {
  description = "Subdomain that the main project will run on. e.g. election"
  default     = "election"
}

variable "aws_profile_name" {
  description = "Name of the AWS profile used"
  default = "default"
}
