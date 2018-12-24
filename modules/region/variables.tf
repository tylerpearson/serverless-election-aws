variable "zone_id" {
  description = "Id of the Route 53 zone"
}

variable "api_subdomain" {
  description = "Subdomain that the API gateway is available on"
  default     = "api"
}
