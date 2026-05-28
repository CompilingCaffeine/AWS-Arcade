# Security Best Practices

## In place

- Both S3 buckets are private with all public access blocked.
- Public traffic is served only through CloudFront with Origin Access Control.
- TLS is enforced on S3 access via bucket policies (deny `aws:SecureTransport = false`).
- Lambda uses least-privilege IAM:
  - read only from the upload bucket under `incoming/*`
  - write only to `games/*` and `catalog/*` in the site bucket
  - access only the catalog DynamoDB table
  - invalidate only the configured CloudFront distribution
  - send messages only to its own DLQ
- GitHub Actions assumes an IAM role via OIDC; no static keys.
- Terraform state is in an encrypted, versioned S3 bucket; locks held in DynamoDB and native S3 lockfile.
- `terraform.tfvars`, `backend.hcl`, and state files are gitignored.
- ZIP paths are normalized and rejected if they escape the root.
- File count, ZIP size, and uncompressed size are bounded.
- The Lambda validates manifests against `schemas/manifest.schema.json` (JSON Schema 2020-12).
- CloudFront response-headers policies enforce CSP, HSTS, X-Content-Type-Options, Referrer-Policy, and Permissions-Policy. The portfolio uses a strict CSP; `/games/*` uses a CSP permissive enough to run self-contained HTML5 games (`'unsafe-inline'` for script/style).
- A CloudTrail trail logs management events for the region plus global service events to a private, encrypted audit bucket with lifecycle expiration.
- S3 server access logs from both the upload and site buckets are delivered to the same audit bucket under `s3-access/<bucket-name>/`.
- A dead-letter SQS queue captures failed Lambda invocations after Lambda's async retries.
- CloudWatch alarms publish to an SNS topic for: Lambda errors > 0 and DLQ depth > 0. Set `alarm_email` to subscribe.

## Still to add

- Malware scanning of uploaded ZIPs before publish (e.g., ClamAV via separate Lambda layer or AWS GuardDuty Malware Protection on S3).
- A signed/authenticated upload flow before allowing untrusted uploaders (presigned PUT via API Gateway + Cognito or a lambda authorizer).
- AWS WAF on the CloudFront distribution.
- KMS customer-managed keys (CMK) on S3, SNS, SQS, and DynamoDB if compliance regimes require it.

