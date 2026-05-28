# MVP Milestone

## Goal

Ship the smallest production-shaped platform that can publish static HTML5 games automatically from ZIP upload to public CloudFront availability.

## Included

- Terraform remote state bootstrap with encrypted S3 state and DynamoDB lock table.
- Modular Terraform for storage, catalog, CDN, certificate/DNS, and Lambda pipeline.
- Private S3 uploads bucket.
- Private S3 site bucket.
- CloudFront distribution using Origin Access Control.
- Optional Route53 aliases for `play.herzi.ai` and `games.herzi.ai`.
- Optional ACM certificate automation in `us-east-1`.
- DynamoDB catalog table.
- Lambda package processor for validation, deployment, catalog update, and invalidation.
- Static frontend that renders from `catalog/catalog.json`.
- GitHub Actions workflow for plan on PR and apply on main.

## Excluded Until Milestone 2

- Authenticated uploader UI.
- Presigned upload API.
- Moderation or malware scanning.
- Step Functions orchestration.
- Preview environments per game.
- Advanced game analytics.
- Admin dashboard.

## Acceptance Criteria

- `terraform apply` provisions all MVP infrastructure.
- Uploading a valid ZIP to `incoming/` deploys the game to `/games/{game_id}/`.
- Invalid packages fail without writing public game files.
- `catalog/catalog.json` is updated after a successful upload.
- CloudFront invalidation is created for the game path and catalog.
- The portfolio homepage renders games from the catalog.
- S3 buckets remain private.
- IAM policies are scoped to the required buckets, table, logs, and CloudFront distribution.

## MVP Test Package

Use:

```bash
bash scripts/create-sample-game-zip.sh
aws s3 cp /tmp/sample-game.zip s3://<upload-bucket>/incoming/sample-game.zip
```

