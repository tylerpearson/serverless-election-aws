output "api_url" {
  value = "https://${var.api_subdomain}.${var.project_subdomain}.${data.aws_route53_zone.root_domain.name}"
}
