# Local Development

## Prerequisites

- Terraform 1.10 or newer.
- AWS CLI v2.
- Python 3.12.
- An AWS account with permission to create S3, Lambda, CloudFront, DynamoDB, IAM, Route53, and ACM resources.
- A Route53 public hosted zone for `herzi.ai` if enabling custom domains.

## Bootstrap Remote State

Run this once per AWS account/region:

```bash
terraform -chdir=terraform/envs/bootstrap init
terraform -chdir=terraform/envs/bootstrap apply \
  -var='project_name=game-publishing-platform' \
  -var='aws_region=us-west-2'
```

Create `terraform/envs/prod/backend.hcl` from the outputs:

```hcl
bucket         = "..."
key            = "prod/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "..."
use_lockfile   = true
encrypt        = true
```

## Configure Prod Variables

Copy:

```bash
cp terraform/envs/prod/terraform.tfvars.example terraform/envs/prod/terraform.tfvars
```

For the fastest MVP, leave `enable_custom_domain = false`. Enable domains after the hosted zone exists and names are confirmed.

## Deploy

```bash
terraform -chdir=terraform/envs/prod init -backend-config=backend.hcl
terraform -chdir=terraform/envs/prod fmt -recursive
terraform -chdir=terraform/envs/prod validate
terraform -chdir=terraform/envs/prod plan -var-file=terraform.tfvars
terraform -chdir=terraform/envs/prod apply -var-file=terraform.tfvars
```

## Test Lambda Code Locally

```bash
python3 -m venv .venv
.venv/bin/pip install -r lambdas/package_processor/requirements-dev.txt
.venv/bin/pytest lambdas/package_processor/tests/
```

## Preview the Static Frontend

The local `frontend/public/catalog/catalog.json` file contains sample catalog data for browser preview only. Terraform excludes that local preview file and creates the deployed initial catalog object separately.

```bash
python3 -m http.server 8080 --directory frontend/public
```

## Create a Sample ZIP

```bash
bash scripts/create-sample-game-zip.sh
```

## Upload the Sample ZIP

```bash
UPLOAD_BUCKET=$(terraform -chdir=terraform/envs/prod output -raw upload_bucket_name)
aws s3 cp /tmp/sample-game.zip "s3://${UPLOAD_BUCKET}/incoming/sample-game.zip"
```

Then open:

```bash
terraform -chdir=terraform/envs/prod output -raw portfolio_url
```
