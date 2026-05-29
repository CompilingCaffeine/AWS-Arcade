resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.name_prefix}-api"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }

  tags = var.tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name_prefix}-cognito"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = var.cognito_issuer
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      routeKey           = "$context.routeKey"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      integrationStatus  = "$context.integration.status"
      integrationLatency = "$context.integration.latency"
    })
  }

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 10
  }

  tags = var.tags
}

locals {
  common_endpoint_args = {
    api_id             = aws_apigatewayv2_api.this.id
    api_execution_arn  = aws_apigatewayv2_api.this.execution_arn
    authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
    log_retention_days = var.log_retention_days
    tags               = var.tags
  }
}

# -----------------------------------------------------------------------------
# presign — POST /uploads
# -----------------------------------------------------------------------------

module "presign" {
  source = "../lambda-endpoint"

  function_name      = "${var.name_prefix}-presign"
  source_dir         = var.source_dir
  memory_size        = var.lambda_memory_size
  timeout            = var.lambda_timeout_seconds
  api_id             = local.common_endpoint_args.api_id
  api_execution_arn  = local.common_endpoint_args.api_execution_arn
  authorizer_id      = local.common_endpoint_args.authorizer_id
  log_retention_days = local.common_endpoint_args.log_retention_days
  tags               = local.common_endpoint_args.tags

  routes = ["POST /uploads"]

  environment_variables = {
    UPLOAD_BUCKET          = var.upload_bucket_name
    PRESIGNED_URL_TTL_SECS = tostring(var.presigned_url_ttl_seconds)
    MAX_UPLOAD_BYTES       = tostring(var.max_upload_bytes)
  }

  iam_statements = [
    {
      sid       = "PresignedUploadObjects"
      actions   = ["s3:PutObject"]
      resources = ["${var.upload_bucket_arn}/incoming/*"]
    },
  ]
}

# -----------------------------------------------------------------------------
# my_uploads — GET /me/uploads
# -----------------------------------------------------------------------------

module "my_uploads" {
  source = "../lambda-endpoint"

  function_name      = "${var.name_prefix}-my-uploads"
  source_dir         = var.my_uploads_source_dir
  memory_size        = var.lambda_memory_size
  timeout            = var.lambda_timeout_seconds
  api_id             = local.common_endpoint_args.api_id
  api_execution_arn  = local.common_endpoint_args.api_execution_arn
  authorizer_id      = local.common_endpoint_args.authorizer_id
  log_retention_days = local.common_endpoint_args.log_retention_days
  tags               = local.common_endpoint_args.tags

  routes = ["GET /me/uploads"]

  environment_variables = {
    CATALOG_TABLE = var.catalog_table_name
  }

  iam_statements = [
    {
      sid       = "ScanCatalog"
      actions   = ["dynamodb:Scan"]
      resources = [var.catalog_table_arn]
    },
  ]
}

# -----------------------------------------------------------------------------
# admin_handler — GET /admin/pending, POST /admin/games/{id}/promote|reject
# -----------------------------------------------------------------------------

module "admin_handler" {
  source = "../lambda-endpoint"

  function_name      = "${var.name_prefix}-admin"
  source_dir         = var.admin_handler_source_dir
  memory_size        = var.lambda_memory_size
  timeout            = 60
  api_id             = local.common_endpoint_args.api_id
  api_execution_arn  = local.common_endpoint_args.api_execution_arn
  authorizer_id      = local.common_endpoint_args.authorizer_id
  log_retention_days = local.common_endpoint_args.log_retention_days
  tags               = local.common_endpoint_args.tags

  routes = [
    "GET /admin/pending",
    "POST /admin/games/{game_id}/promote",
    "POST /admin/games/{game_id}/reject",
  ]

  environment_variables = {
    SITE_BUCKET                = var.site_bucket_name
    CATALOG_TABLE              = var.catalog_table_name
    CLOUDFRONT_DISTRIBUTION_ID = var.cloudfront_distribution_id
    SENDER_EMAIL               = var.sender_email
    ADMIN_EMAIL                = var.admin_email
    PORTFOLIO_HOSTNAME         = var.portfolio_hostname
  }

  iam_statements = [
    {
      sid = "ManageSiteObjects"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = [
        "${var.site_bucket_arn}/games/*",
        "${var.site_bucket_arn}/staging/*",
        "${var.site_bucket_arn}/catalog/*",
      ]
    },
    {
      sid       = "ListSiteObjects"
      actions   = ["s3:ListBucket"]
      resources = [var.site_bucket_arn]
      conditions = [{
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["games/*", "staging/*", "catalog/*"]
      }]
    },
    {
      sid       = "UpdateCatalog"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan"]
      resources = [var.catalog_table_arn]
    },
    {
      sid       = "CreateCloudFrontInvalidations"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [var.cloudfront_distribution_arn]
    },
    {
      sid       = "SendNotificationEmails"
      actions   = ["ses:SendEmail"]
      resources = [var.sender_identity_arn]
    },
  ]
}
