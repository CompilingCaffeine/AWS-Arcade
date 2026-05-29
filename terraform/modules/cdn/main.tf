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

resource "aws_cloudfront_response_headers_policy" "portfolio" {
  name    = "${var.name_prefix}-portfolio-headers"
  comment = "Strict security headers for the portfolio and catalog"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self' https://*.amazoncognito.com https://*.execute-api.us-east-1.amazonaws.com; form-action 'self' https://*.amazoncognito.com; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
      override                = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=(), gyroscope=(), accelerometer=(), fullscreen=(self)"
      override = true
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "games" {
  name    = "${var.name_prefix}-games-headers"
  comment = "Permissive CSP for self-contained HTML5 games at /games/*"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
      override                = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=(), gyroscope=(self), accelerometer=(self), fullscreen=(self)"
      override = true
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
    target_origin_id           = "site-s3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.default.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.portfolio.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.uri_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/catalog/*"
    target_origin_id           = "site-s3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.catalog.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.portfolio.id
  }

  ordered_cache_behavior {
    path_pattern               = "/games/*"
    target_origin_id           = "site-s3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.default.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.games.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.uri_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/staging/*"
    target_origin_id           = "site-s3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.default.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.games.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.uri_rewrite.arn
    }
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

