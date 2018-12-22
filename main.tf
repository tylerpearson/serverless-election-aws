locals {
  api_subdomain = "api"
  domain_name   = "tylerpearson.cloud"
  project_zone  = "election"
  static_domain = "${local.project_zone}.${local.domain_name}"
}

data "aws_route53_zone" "root_domain" {
  provider = "aws.us-east-1"
  name     = "${local.domain_name}." # move to a tfvars file
}

resource "aws_route53_zone" "voting_zone" {
  provider = "aws.us-east-1"
  name     = "${local.project_zone}.${data.aws_route53_zone.root_domain.name}" # move to a tfvars file
}

resource "aws_route53_record" "voting_zone_ns" {
  provider = "aws.us-east-1"
  zone_id  = "${data.aws_route53_zone.root_domain.zone_id}"
  name     = "${aws_route53_zone.voting_zone.name}"
  type     = "NS"
  ttl      = "60"

  records = [
    "${aws_route53_zone.voting_zone.name_servers.0}",
    "${aws_route53_zone.voting_zone.name_servers.1}",
    "${aws_route53_zone.voting_zone.name_servers.2}",
    "${aws_route53_zone.voting_zone.name_servers.3}",
  ]

  depends_on = ["aws_route53_zone.voting_zone"]
}

module "us_east_1" {
  source = "modules/region"

  zone_id = "${aws_route53_zone.voting_zone.id}"

  providers = {
    aws = "aws.us-east-1"
  }
}

output "us_east_1_invocation_url" {
  value = "${module.us_east_1.invocation_url}"
}

# module "us_east_2" {
#   source = "modules/region"

#   zone_id = "${aws_route53_zone.voting_zone.id}"

#   providers = {
#     aws = "aws.us-east-2"
#   }
# }

# output "us_east_2_invocation_url" {
#   value = "${module.us_east_2.invocation_url}"
# }

module "us_west_1" {
  source = "modules/region"

  zone_id = "${aws_route53_zone.voting_zone.id}"

  providers = {
    aws = "aws.us-west-1"
  }
}

output "us_west_1_invocation_url" {
  value = "${module.us_west_1.invocation_url}"
}

# module "us_west_2" {
#   source = "modules/region"

#   zone_id = "${aws_route53_zone.voting_zone.id}"

#   providers = {
#     aws = "aws.us-west-2"
#   }
# }

# output "us_west_2_invocation_url" {
#   value = "${module.us_west_2.invocation_url}"
# }

# Global

resource "aws_dynamodb_global_table" "voters_global_table" {
  # depends_on = ["module.us_east_1", "module.us_west_1", "module.us_east_2", "module.us_west_2"]
  depends_on = ["module.us_east_1", "module.us_west_1"]
  provider   = "aws.us-east-1"

  name = "voters"

  replica {
    region_name = "us-east-1"
  }

  # replica {
  #   region_name = "us-east-2"
  # }

  replica {
    region_name = "us-west-1"
  }

  # replica {
  #   region_name = "us-west-2"
  # }
}

resource "aws_dynamodb_global_table" "results_global_table" {
  # depends_on = ["module.us_east_1", "module.us_west_1", "module.us_east_2", "module.us_west_2"]
  depends_on = ["module.us_east_1", "module.us_west_1"]
  provider   = "aws.us-east-1"

  name = "results"

  replica {
    region_name = "us-east-1"
  }

  # replica {
  #   region_name = "us-east-2"
  # }

  replica {
    region_name = "us-west-1"
  }

  # replica {
  #   region_name = "us-west-2"
  # }
}

# Website

resource "aws_s3_bucket" "static" {
  provider = "aws.us-east-1"
  bucket   = "${local.static_domain}"
  acl      = "public-read"

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid": "AddPerm",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${local.static_domain}/*"]
    }
  ]
}
POLICY

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  versioning {
    enabled = true
  }

  # logging {
  #   target_bucket = "${aws_s3_bucket.log_bucket.id}"
  #   target_prefix = "log/"
  # }
}

resource "null_resource" "sync_website" {
  triggers = {
    policy_sha1 = "${sha1(file("website/index.html"))}"
  }

  provisioner "local-exec" {
    command = "aws s3 sync website/ s3://${aws_s3_bucket.static.id}/ --acl public-read --profile tyler-personal-election " # TODO: make profile a variable
  }
}

data "aws_acm_certificate" "static_ssl_cert" {
  provider    = "aws.us-east-1"
  domain      = "${local.static_domain}"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

resource "aws_cloudfront_distribution" "static_website_cdn" {
  provider        = "aws.us-east-1"
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.static.id}"
    domain_name = "${aws_s3_bucket.static.website_endpoint}"

    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = "80"
      https_port             = "443"
      origin_ssl_protocols   = ["TLSv1"]
    }
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    min_ttl                = "0"
    default_ttl            = "300"
    max_ttl                = "1200"
    target_origin_id       = "origin-bucket-${aws_s3_bucket.static.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  # logging should be turned on for the page
  # https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#logging_config

  restrictions {
    geo_restriction {
      restriction_type = "none"

      # This clould theoretically be restricted to the US for an election
      # restriction_type = "whitelist"
      # locations        = ["US"]
    }
  }
  viewer_certificate {
    acm_certificate_arn      = "${data.aws_acm_certificate.static_ssl_cert.arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }
  aliases = ["${local.static_domain}"]

  # add a failover to secondary bucket here?
}

resource "aws_route53_record" "static_record" {
  provider = "aws.us-east-1"
  zone_id  = "${aws_route53_zone.voting_zone.id}"
  name     = "${local.static_domain}"
  type     = "A"

  alias {
    name    = "${aws_cloudfront_distribution.static_website_cdn.domain_name}"
    zone_id = "${aws_cloudfront_distribution.static_website_cdn.hosted_zone_id}"

    # evaluate_target_health = true
    evaluate_target_health = false
  }

  depends_on = ["aws_cloudfront_distribution.static_website_cdn"]
}

output "api_url" {
  value = "https://${local.api_subdomain}.${local.project_zone}.${data.aws_route53_zone.root_domain.name}"
}
