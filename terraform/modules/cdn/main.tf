resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name_prefix}-site-oac"
  description                       = "OAC for ${var.site_bucket_id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "uri_rewrite" {
  name    = "${var.name_prefix}-uri-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite directory paths to index.html for private S3 origin"
  publish = true
  code    = file("${path.module}/uri-rewrite.js")
}

resource "aws_cloudfront_cache_policy" "default" {
  name        = "${var.name_prefix}-default-cache"
  comment     = "Default static asset caching"
  default_ttl = 3600
  max_ttl     = 86400
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "catalog" {
  name        = "${var.name_prefix}-catalog-cache"
  comment     = "Short cache for generated public catalog"
  default_ttl = 30
  max_ttl     = 60
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} static arcade distribution"
  default_root_object = "index.html"
  aliases             = var.aliases
  price_class         = var.price_class
  http_version        = "http2and3"
  tags                = var.tags

  origin {
    domain_name              = var.site_bucket_regional_domain_name
    origin_id                = "site-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "site-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.default.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.uri_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/catalog/*"
    target_origin_id       = "site-s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = aws_cloudfront_cache_policy.catalog.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = length(var.aliases) > 0 ? var.acm_certificate_arn : null
    cloudfront_default_certificate = length(var.aliases) == 0
    minimum_protocol_version       = length(var.aliases) > 0 ? "TLSv1.2_2021" : null
    ssl_support_method             = length(var.aliases) > 0 ? "sni-only" : null
  }
}

