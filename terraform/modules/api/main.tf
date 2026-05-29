locals {
  function_name = "${var.name_prefix}-presign"
}

data "archive_file" "request_upload_url" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.root}/.terraform/${local.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "PresignedUploadObjects"
    actions   = ["s3:PutObject"]
    resources = ["${var.upload_bucket_arn}/incoming/*"]
  }

  statement {
    sid       = "WriteXRayTraceSegments"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "request_upload_url" {
  # checkov:skip=CKV_AWS_116: synchronous Lambda invoked by API Gateway; DLQ does not apply.
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.request_upload_url.output_path
  source_code_hash = data.archive_file.request_upload_url.output_base64sha256
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout_seconds
  tags             = var.tags

  environment {
    variables = {
      UPLOAD_BUCKET          = var.upload_bucket_name
      PRESIGNED_URL_TTL_SECS = tostring(var.presigned_url_ttl_seconds)
      MAX_UPLOAD_BYTES       = tostring(var.max_upload_bytes)
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]
}

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

resource "aws_apigatewayv2_integration" "request_upload_url" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.request_upload_url.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_uploads" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /uploads"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.request_upload_url.id}"
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

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.request_upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# my_uploads Lambda: GET /me/uploads
# -----------------------------------------------------------------------------

locals {
  my_uploads_function_name = "${var.name_prefix}-my-uploads"
}

data "archive_file" "my_uploads" {
  type        = "zip"
  source_dir  = var.my_uploads_source_dir
  output_path = "${path.root}/.terraform/${local.my_uploads_function_name}.zip"
}

resource "aws_cloudwatch_log_group" "my_uploads" {
  name              = "/aws/lambda/${local.my_uploads_function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "my_uploads" {
  name               = "${local.my_uploads_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "my_uploads" {
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.my_uploads.arn}:*"]
  }

  statement {
    sid       = "ScanCatalog"
    actions   = ["dynamodb:Scan"]
    resources = [var.catalog_table_arn]
  }

  statement {
    sid       = "WriteXRayTraceSegments"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "my_uploads" {
  name   = "${local.my_uploads_function_name}-policy"
  role   = aws_iam_role.my_uploads.id
  policy = data.aws_iam_policy_document.my_uploads.json
}

resource "aws_lambda_function" "my_uploads" {
  # checkov:skip=CKV_AWS_116: synchronous Lambda invoked by API Gateway; DLQ does not apply.
  function_name    = local.my_uploads_function_name
  role             = aws_iam_role.my_uploads.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.my_uploads.output_path
  source_code_hash = data.archive_file.my_uploads.output_base64sha256
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout_seconds
  tags             = var.tags

  environment {
    variables = {
      CATALOG_TABLE = var.catalog_table_name
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_cloudwatch_log_group.my_uploads,
    aws_iam_role_policy.my_uploads,
  ]
}

resource "aws_apigatewayv2_integration" "my_uploads" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.my_uploads.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_my_uploads" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /me/uploads"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.my_uploads.id}"
}

resource "aws_lambda_permission" "apigw_invoke_my_uploads" {
  statement_id  = "AllowAPIGatewayInvokeMyUploads"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_uploads.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# admin_handler Lambda: GET /admin/pending, POST /admin/games/{id}/promote|reject
# -----------------------------------------------------------------------------

locals {
  admin_handler_function_name = "${var.name_prefix}-admin"
}

data "archive_file" "admin_handler" {
  type        = "zip"
  source_dir  = var.admin_handler_source_dir
  output_path = "${path.root}/.terraform/${local.admin_handler_function_name}.zip"
}

resource "aws_cloudwatch_log_group" "admin_handler" {
  name              = "/aws/lambda/${local.admin_handler_function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "admin_handler" {
  name               = "${local.admin_handler_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "admin_handler" {
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.admin_handler.arn}:*"]
  }

  statement {
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
  }

  statement {
    sid       = "ListSiteObjects"
    actions   = ["s3:ListBucket"]
    resources = [var.site_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["games/*", "staging/*", "catalog/*"]
    }
  }

  statement {
    sid = "UpdateCatalog"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan",
    ]
    resources = [var.catalog_table_arn]
  }

  statement {
    sid       = "CreateCloudFrontInvalidations"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.cloudfront_distribution_arn]
  }

  statement {
    sid       = "SendNotificationEmails"
    actions   = ["ses:SendEmail"]
    resources = [var.sender_identity_arn]
  }

  statement {
    sid       = "WriteXRayTraceSegments"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "admin_handler" {
  name   = "${local.admin_handler_function_name}-policy"
  role   = aws_iam_role.admin_handler.id
  policy = data.aws_iam_policy_document.admin_handler.json
}

resource "aws_lambda_function" "admin_handler" {
  # checkov:skip=CKV_AWS_116: synchronous Lambda invoked by API Gateway; DLQ does not apply.
  function_name    = local.admin_handler_function_name
  role             = aws_iam_role.admin_handler.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.admin_handler.output_path
  source_code_hash = data.archive_file.admin_handler.output_base64sha256
  memory_size      = var.lambda_memory_size
  timeout          = 60
  tags             = var.tags

  environment {
    variables = {
      SITE_BUCKET                = var.site_bucket_name
      CATALOG_TABLE              = var.catalog_table_name
      CLOUDFRONT_DISTRIBUTION_ID = var.cloudfront_distribution_id
      SENDER_EMAIL               = var.sender_email
      ADMIN_EMAIL                = var.admin_email
      PORTFOLIO_HOSTNAME         = var.portfolio_hostname
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_cloudwatch_log_group.admin_handler,
    aws_iam_role_policy.admin_handler,
  ]
}

resource "aws_apigatewayv2_integration" "admin_handler" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.admin_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_admin_pending" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /admin/pending"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.admin_handler.id}"
}

resource "aws_apigatewayv2_route" "post_admin_promote" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /admin/games/{game_id}/promote"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.admin_handler.id}"
}

resource "aws_apigatewayv2_route" "post_admin_reject" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /admin/games/{game_id}/reject"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.admin_handler.id}"
}

resource "aws_lambda_permission" "apigw_invoke_admin_handler" {
  statement_id  = "AllowAPIGatewayInvokeAdmin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
