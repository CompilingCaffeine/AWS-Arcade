data "aws_caller_identity" "current" {}

locals {
  name_prefix  = "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  domain_names = var.enable_custom_domain ? var.domain_names : []
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "observability" {
  source = "../../modules/observability"

  name_prefix        = local.name_prefix
  account_id         = data.aws_caller_identity.current.account_id
  log_retention_days = var.audit_log_retention_days
  alarm_email        = var.alarm_email
  force_destroy      = var.force_destroy_buckets
  tags               = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  name_prefix           = local.name_prefix
  force_destroy         = var.force_destroy_buckets
  upload_retention_days = var.upload_retention_days
  access_logs_bucket    = module.observability.audit_bucket_id
  tags                  = local.common_tags
}

module "catalog" {
  source = "../../modules/catalog"

  name_prefix = local.name_prefix
  enable_pitr = var.enable_catalog_pitr
  tags        = local.common_tags
}

module "certificate" {
  count  = var.enable_custom_domain ? 1 : 0
  source = "../../modules/certificate"

  providers = {
    aws = aws.us_east_1
  }

  hosted_zone_name = var.hosted_zone_name
  domain_names     = local.domain_names
  tags             = local.common_tags
}

module "cdn" {
  source = "../../modules/cdn"

  name_prefix                      = local.name_prefix
  site_bucket_id                   = module.storage.site_bucket_id
  site_bucket_regional_domain_name = module.storage.site_bucket_regional_domain_name
  aliases                          = local.domain_names
  acm_certificate_arn              = var.enable_custom_domain ? module.certificate[0].certificate_arn : null
  price_class                      = var.cloudfront_price_class
  tags                             = local.common_tags
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${module.storage.site_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.distribution_arn]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      module.storage.site_bucket_arn,
      "${module.storage.site_bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = module.storage.site_bucket_id
  policy = data.aws_iam_policy_document.site_bucket.json
}

module "lambda_pipeline" {
  source = "../../modules/lambda-pipeline"

  name_prefix                    = local.name_prefix
  source_dir                     = "${path.root}/../../../lambdas/package_processor"
  schema_file                    = "${path.root}/../../../schemas/manifest.schema.json"
  upload_bucket_arn              = module.storage.upload_bucket_arn
  site_bucket_arn                = module.storage.site_bucket_arn
  site_bucket_name               = module.storage.site_bucket_id
  catalog_table_arn              = module.catalog.table_arn
  catalog_table_name             = module.catalog.table_name
  cloudfront_distribution_arn    = module.cdn.distribution_arn
  cloudfront_distribution_id     = module.cdn.distribution_id
  lambda_memory_size             = var.lambda_memory_size
  lambda_timeout_seconds         = var.lambda_timeout_seconds
  alarm_topic_arn                = module.observability.alarm_topic_arn
  frontend_source_dir            = "${path.root}/../../../frontend/public"
  frontend_destination_bucket_id = module.storage.site_bucket_id
  tags                           = local.common_tags

  depends_on = [aws_s3_bucket_policy.site]
}

resource "aws_lambda_permission" "allow_upload_bucket" {
  statement_id  = "AllowExecutionFromUploadBucket"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_pipeline.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.storage.upload_bucket_arn
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = module.storage.upload_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_pipeline.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
    filter_suffix       = ".zip"
  }

  depends_on = [aws_lambda_permission.allow_upload_bucket]
}

module "dns_records" {
  count  = var.enable_custom_domain ? 1 : 0
  source = "../../modules/dns-records"

  hosted_zone_name            = var.hosted_zone_name
  domain_names                = local.domain_names
  distribution_domain_name    = module.cdn.distribution_domain_name
  distribution_hosted_zone_id = module.cdn.distribution_hosted_zone_id
}
