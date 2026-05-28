# Future Extensibility

- Add an API Gateway + Lambda uploader service that returns presigned S3 upload URLs.
- Add Cognito or IAM Identity Center for admin upload authentication.
- Replace direct S3 notification with EventBridge when multiple consumers need upload events.
- Add Step Functions for validation, scan, deploy, catalog, and rollback stages.
- Add a malware scanning Lambda or third-party scanning integration.
- Add image thumbnail generation.
- Add game moderation status: `draft`, `published`, `rejected`, `archived`.
- Add preview deployments under `previews/{upload_id}/`.
- Add CloudFront Functions or Lambda@Edge for custom routing and security headers.
- Add analytics through CloudFront logs, Kinesis Firehose, Athena, or a privacy-preserving event API.
- Add multi-environment Terraform folders for `dev`, `stage`, and `prod`.
- Add OpenSearch or Algolia if catalog search grows beyond simple client-side filtering.
- Add content hashing so immutable game assets can use year-long browser cache headers safely.

