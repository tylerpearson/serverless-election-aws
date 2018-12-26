output "us_east_1_invocation_url" {
  value = "${module.us_east_1.invocation_url}"
}

output "us_west_1_invocation_url" {
  value = "${module.us_west_1.invocation_url}"
}

output "api_url" {
  value = "https://${var.api_subdomain}.${local.static_domain}${module.us_east_1.api_resource}"
}

output "website_url" {
  value = "https://${local.static_domain}"
}
