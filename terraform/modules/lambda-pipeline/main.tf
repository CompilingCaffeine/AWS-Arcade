locals {
  function_name     = "${var.name_prefix}-package-processor"
  build_script      = abspath("${path.module}/../../../scripts/build-lambda.sh")
  lambda_source_dir = abspath(var.source_dir)
  lambda_schema     = abspath(var.schema_file)
  lambda_build_dir  = abspath("${path.root}/.terraform/lambda-build/${local.function_name}")

  lambda_build_hash = sha256(join("", concat(
    [for f in fileset(var.source_dir, "*.py") : filesha256("${var.source_dir}/${f}")],
    [filesha256("${var.source_dir}/requirements.txt"), filesha256(var.schema_file)],
  )))

  frontend_files = fileset(var.frontend_source_dir, "**")
  content_types = {
    css  = "text/css"
    html = "text/html"
    js   = "application/javascript"
    json = "application/json"
    svg  = "image/svg+xml"
    txt  = "text/plain"
  }
  frontend_objects = {
    for file in local.frontend_files : file => {
      content_type = lookup(local.content_types, try(lower(regex("[^.]+$", file)), ""), "application/octet-stream")
      source       = "${var.frontend_source_dir}/${file}"
    }
    if !endswith(file, "/") && file != "catalog/catalog.json"
  }
}

resource "terraform_data" "lambda_build" {
  triggers_replace = {
    build_hash = local.lambda_build_hash
  }

  provisioner "local-exec" {
    command = "bash '${local.build_script}' '${local.lambda_source_dir}' '${local.lambda_schema}' '${local.lambda_build_dir}'"
  }
}

data "archive_file" "package_processor" {
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = "${path.root}/.terraform/${local.function_name}.zip"

  depends_on = [terraform_data.lambda_build]
}

resource "aws_cloudwatch_log_group" "package_processor" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "package_processor" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "package_processor" {
  statement {
    sid = "WriteLambdaLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.package_processor.arn}:*"]
  }

  statement {
    sid = "ReadUploadedPackages"
    actions = [
      "s3:GetObject",
    ]
    resources = ["${var.upload_bucket_arn}/incoming/*"]
  }

  statement {
    sid       = "ListUploads"
    actions   = ["s3:ListBucket"]
    resources = [var.upload_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["incoming/*"]
    }
  }

  statement {
    sid = "WriteGameSiteObjects"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${var.site_bucket_arn}/games/*",
      "${var.site_bucket_arn}/catalog/*",
    ]
  }

  statement {
    sid       = "ListGameSiteObjects"
    actions   = ["s3:ListBucket"]
    resources = [var.site_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "games/*",
        "catalog/*",
      ]
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
}

resource "aws_iam_role_policy" "package_processor" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.package_processor.id
  policy = data.aws_iam_policy_document.package_processor.json
}

resource "aws_lambda_function" "package_processor" {
  function_name    = local.function_name
  role             = aws_iam_role.package_processor.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.package_processor.output_path
  source_code_hash = data.archive_file.package_processor.output_base64sha256
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout_seconds
  tags             = var.tags

  environment {
    variables = {
      CATALOG_TABLE              = var.catalog_table_name
      CLOUDFRONT_DISTRIBUTION_ID = var.cloudfront_distribution_id
      SITE_BUCKET                = var.site_bucket_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.package_processor,
    aws_iam_role_policy.package_processor,
  ]
}

resource "aws_s3_object" "frontend" {
  for_each = local.frontend_objects

  bucket       = var.frontend_destination_bucket_id
  key          = each.key
  source       = each.value.source
  etag         = filemd5(each.value.source)
  content_type = each.value.content_type
  cache_control = each.key == "index.html" ? "public,max-age=60" : (
    startswith(each.key, "catalog/") ? "public,max-age=30" : "public,max-age=3600"
  )
}

resource "aws_s3_object" "initial_catalog" {
  bucket        = var.frontend_destination_bucket_id
  key           = "catalog/catalog.json"
  content       = jsonencode({ generated_at = 0, games = [] })
  content_type  = "application/json"
  cache_control = "public,max-age=30"

  lifecycle {
    ignore_changes = [content, etag]
  }
}
