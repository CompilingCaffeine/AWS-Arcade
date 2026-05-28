# game-publishing-platform

Serverless AWS platform for publishing AI-generated static HTML5 arcade games.

The MVP flow is:

1. Upload a game ZIP to the private uploads S3 bucket under `incoming/`.
2. S3 invokes the package processor Lambda.
3. Lambda validates the package and reads `manifest.json`.
4. Lambda deploys the static files to the private site S3 bucket under `games/{game_id}/`.
5. Lambda upserts the DynamoDB game catalog record.
6. Lambda writes `catalog/catalog.json` for the static frontend.
7. Lambda invalidates the relevant CloudFront paths.
8. CloudFront serves the portfolio and games publicly.

## Repository Structure

```text
game-publishing-platform/
├── .github/workflows/terraform.yml
├── docs/
│   ├── architecture.md
│   ├── cost-optimization.md
│   ├── future-extensibility.md
│   ├── local-development.md
│   ├── mvp-milestone.md
│   ├── security.md
│   └── upload-pipeline.md
├── examples/sample-game/
│   ├── index.html
│   └── manifest.json
├── frontend/public/
│   ├── app.js
│   ├── index.html
│   └── styles.css
├── lambdas/package_processor/
│   ├── handler.py
│   └── requirements.txt
├── schemas/manifest.schema.json
├── scripts/create-sample-game-zip.sh
└── terraform/
    ├── envs/
    │   ├── bootstrap/
    │   └── prod/
    └── modules/
        ├── catalog/
        ├── cdn/
        ├── certificate/
        ├── dns-records/
        ├── lambda-pipeline/
        └── storage/
```

## Why This Architecture

- **S3 + CloudFront** keeps hosting static games cheap, durable, and globally cached.
- **CloudFront Origin Access Control** keeps the site bucket private while still serving public traffic.
- **S3 event notifications** are the lowest-cost event trigger for the MVP upload pipeline.
- **Lambda** is enough for ZIP validation, extraction, metadata writes, and CloudFront invalidation without servers.
- **DynamoDB on-demand billing** keeps the central catalog simple and Free Tier friendly.
- **A generated `catalog/catalog.json`** lets the frontend stay purely static and cacheable.
- **Route53 + ACM** are optional in MVP so the platform can deploy before DNS is ready.
- **Terraform modules** separate storage, CDN, catalog, DNS, and pipeline ownership.

## First MVP Milestone

The first milestone provisions the production-ready minimum:

- Remote state bootstrap resources.
- Private uploads and site buckets.
- DynamoDB catalog table.
- CloudFront distribution with OAC and directory-index rewrites.
- Lambda package processor with least-privilege IAM.
- Static portfolio frontend files deployed by Terraform.
- GitHub Actions plan/apply workflow.

See [docs/mvp-milestone.md](docs/mvp-milestone.md) for scope and acceptance criteria.

## Quick Start

Bootstrap Terraform state once:

```bash
terraform -chdir=terraform/envs/bootstrap init
terraform -chdir=terraform/envs/bootstrap apply \
  -var='project_name=game-publishing-platform' \
  -var='aws_region=us-west-2'
```

Copy the bootstrap outputs into `terraform/envs/prod/backend.hcl`, then deploy:

```bash
terraform -chdir=terraform/envs/prod init -backend-config=backend.hcl
terraform -chdir=terraform/envs/prod plan -var-file=terraform.tfvars
terraform -chdir=terraform/envs/prod apply -var-file=terraform.tfvars
```

Create and upload the sample game:

```bash
bash scripts/create-sample-game-zip.sh
aws s3 cp /tmp/sample-game.zip s3://$(terraform -chdir=terraform/envs/prod output -raw upload_bucket_name)/incoming/sample-game.zip
```

## GitHub Actions Configuration

Set these repository values before enabling apply on `main`:

- Secret `AWS_TERRAFORM_ROLE_ARN`: IAM role assumed through GitHub OIDC.
- Variable `AWS_REGION`: primary AWS region, for example `us-west-2`.
- Variable `TF_STATE_BUCKET`: remote state bucket from the bootstrap output.
- Variable `TF_LOCK_TABLE`: DynamoDB lock table from the bootstrap output.
