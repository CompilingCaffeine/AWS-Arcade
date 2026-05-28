# Security Best Practices

- Keep both S3 buckets private and block all public access.
- Serve public traffic only through CloudFront Origin Access Control.
- Enforce TLS for S3 access with bucket policies.
- Use least-privilege Lambda IAM:
  - read only from the upload bucket
  - write only to `games/*` and `catalog/*` in the site bucket
  - access only the catalog DynamoDB table
  - invalidate only the configured CloudFront distribution
- Use GitHub Actions OIDC instead of static AWS access keys.
- Put Terraform state in an encrypted S3 bucket with versioning enabled.
- Use DynamoDB locking, and native S3 lockfiles where supported by your Terraform version.
- Keep `terraform.tfvars`, backend files, and state files out of git.
- Validate ZIP paths to prevent path traversal.
- Enforce file count and archive size limits to reduce Lambda abuse risk.
- Add malware scanning before broader public uploads.
- Add signed uploader flows before allowing untrusted users to upload.
- Enable CloudTrail, S3 server access logs or CloudFront logs, and alarms in production accounts.

