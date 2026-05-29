# Handoff — AWS Arcade Game Publishing Platform

Pick up here in a new session by reading this file first, then [README.md](../README.md), then [docs/architecture.md](architecture.md).

## Elevator pitch

Serverless AWS platform for publishing AI-generated static HTML5 arcade games. Public sign-up via Cognito, manual admin approval before any game goes live, SES email notifications. Built around an S3 + CloudFront + Lambda + DynamoDB + API Gateway HTTP API + Cognito stack provisioned by Terraform.

## Where things stand (as of last commit `55ad2fe`)

- **Live and working** on AWS account `304119515519` in `us-east-1`
- **Portfolio**: https://d24v7tjjj0qnz0.cloudfront.net/
- **Full gated upload flow** has been end-to-end verified via CLI: signup → presigned URL → PUT → stage → admin promote → published in catalog → SES emails delivered
- Six commits on `main`, each a logical milestone (see [Build chronology](#build-chronology) below)
- All tests, tflint, and checkov are green locally

## Quick start for next session

```bash
# 1. Authenticate (one-time per session — SSO token expires)
aws sso login --profile AdministratorAccess-304119515519
export AWS_PROFILE=AdministratorAccess-304119515519
aws sts get-caller-identity   # should return account 304119515519

# 2. Sanity check everything still passes locally
make test           # 71 tests across 4 Lambda suites
/tmp/tflint-bin/tflint --recursive    # (or reinstall: see below)
.venv/bin/checkov --config-file .checkov.yml

# 3. Check live state
terraform -chdir=terraform/envs/prod plan -var-file=terraform.tfvars
# Expected: "No changes."
```

If `/tmp/tflint-bin` is gone, reinstall:
```bash
curl -sL https://github.com/terraform-linters/tflint/releases/latest/download/tflint_darwin_arm64.zip -o /tmp/tflint.zip
unzip -oq /tmp/tflint.zip -d /tmp/tflint-bin/
/tmp/tflint-bin/tflint --init
```

## Live infrastructure cheat sheet

| Thing | Value |
|---|---|
| AWS account | `304119515519` |
| Region | `us-east-1` |
| AWS profile | `AdministratorAccess-304119515519` (SSO) |
| Terraform state | `s3://game-publishing-platform-304119515519-us-east-1-tfstate/prod/terraform.tfstate` |
| State lock table | `game-publishing-platform-304119515519-us-east-1-tflock` |
| CloudFront ID | `E2RIMLRALOUJRW` |
| CF domain | `d24v7tjjj0qnz0.cloudfront.net` |
| Site bucket | `game-publishing-platform-prod-304119515519-site` |
| Upload bucket | `game-publishing-platform-prod-304119515519-uploads` |
| Audit bucket | `game-publishing-platform-prod-304119515519-audit` |
| DynamoDB games | `game-publishing-platform-prod-304119515519-games` |
| Cognito User Pool | `us-east-1_fR0acrCD0` |
| Cognito client ID | `4hnb4lo6dtr3uvpci9av4dvslj` |
| Cognito Hosted UI | `game-publishing-platform-prod-304119515519-auth.auth.us-east-1.amazoncognito.com` |
| API endpoint | `https://zmqz8mh54d.execute-api.us-east-1.amazonaws.com` |
| Lambda DLQ | `game-publishing-platform-prod-304119515519-processor-dlq` |
| SNS alarms topic | `game-publishing-platform-prod-304119515519-alarms` |
| SES sender | `lazare@herzi.ai` (verified, sandbox mode) |
| Admin user | `lazare@herzi.ai` (in `admins` Cognito group) |

Page URLs:
- Portfolio: https://d24v7tjjj0qnz0.cloudfront.net/
- Upload: https://d24v7tjjj0qnz0.cloudfront.net/upload/
- My uploads: https://d24v7tjjj0qnz0.cloudfront.net/my-uploads/
- Admin queue: https://d24v7tjjj0qnz0.cloudfront.net/admin/

API routes (all JWT-authorized):
- `POST /uploads` — uploader requests a presigned PUT URL
- `GET /me/uploads` — uploader lists their own submissions
- `GET /admin/pending` — admin lists `status=pending_review`
- `POST /admin/games/{game_id}/promote` — admin promotes
- `POST /admin/games/{game_id}/reject` — admin rejects

## Build chronology

| Commit | What landed |
|---|---|
| `eca4137` | Initial scaffold + **P0** (schema-driven manifest validation, Lambda build pipeline that vendors `jsonschema`, pytest suite wired into CI). |
| `cb973e4` | **P1** hardening: CloudFront security headers (strict portfolio CSP / permissive games CSP), CloudTrail to a private audit bucket, S3 access logs, SQS DLQ + CloudWatch alarms publishing to SNS. |
| `c7921dc` | **P2** polish: tflint + checkov in CI (with documented skip list), PR plan comment, `Makefile`. |
| `4926e52` | Deploy fixes discovered during first apply: IAM role name length, plan-time `count` evaluation, python3.13 runtime, build hash including the build script, Decimal/list serialization bugs in handler.py. |
| `9a07a59` | **M2a**: Cognito User Pool + Hosted UI, API Gateway HTTP API + JWT authorizer, `request_upload_url` Lambda issuing presigned PUT URLs scoped to `incoming/{user_sub}/{upload_id}.zip`. |
| `3d063e5` | **M2b**: Staging gate. Uploads land in `staging/{upload_id}/` with `status=pending_review`. New `admin_handler` Lambda routes (`GET /admin/pending`, `POST /admin/games/{id}/promote`, `POST /admin/games/{id}/reject`) gated by `cognito:groups` containing `admins`. Three minimal HTML SPA pages (`/upload/`, `/my-uploads/`, `/admin/`) with shared `auth.js` helper. SES sandbox notifications. Email module added. |
| `55ad2fe` | **M2c-1**: Extracted `terraform/modules/lambda-endpoint/` to dedupe ~231 lines of Lambda+IAM+route boilerplate. Each API Lambda is now a ~25-line module call with structured IAM statements (supporting optional condition blocks). |

## The user's M2 decision tree (don't re-litigate)

When the user was asked which shape M2 should take, they picked:
- **Uploaders**: public sign-ups, with self-service signup + email verification via Cognito Hosted UI.
- **Trust posture**: realistically just the user (lazare@herzi.ai). Foreseeable future is "few sign-ups, low volume."
- **Admin**: just lazare@herzi.ai (in `admins` Cognito group).
- **Moderation**: manual review. "Happy to moderate most of v2." No Rekognition / Comprehend / LLM pass.
- **Malware scan (GuardDuty)**: **skipped**. Threat model = "you review everything; content is HTML/JS only; CSP is strict." Scanners wouldn't catch the real risks (fingerprinting JS, CSP bypass, resource hogs) anyway.
- **UI scope**: minimal HTML, three thin pages, no build step. Vanilla JS.
- **SES**: sandbox mode. `lazare@herzi.ai` is both sender and recipient. Production access deferred.
- **Single SES identity**: `lazare@herzi.ai` for all notifications (admin = uploader = sender for now).

## Architecture summary

```
                          ┌───────────────────────┐
                          │  Cognito User Pool    │ Hosted UI + admins group
                          └──────────┬────────────┘
                                     │ JWT (id_token)
                                     ▼
┌──────────────┐  presigned URL ┌────────────────┐
│ /upload/ SPA │ ───────────────│ HTTP API + JWT │ POST /uploads
│ /my-uploads/ │ ←──────────────│  authorizer    │ GET  /me/uploads
│ /admin/      │   list/promote │                │ GET  /admin/pending
└──────────────┘                └─────┬──────────┘ POST /admin/games/{id}/promote
                                      │            POST /admin/games/{id}/reject
                                      ▼
                          ┌───────────────────────┐
                          │ Lambda endpoints      │ presign · my_uploads · admin_handler
                          └──────────┬────────────┘
                                     │
                                     ▼ PUT
                          ┌───────────────────────┐
                          │ S3 incoming/{sub}/    │
                          └──────────┬────────────┘
                                     │ S3 ObjectCreated
                                     ▼
                          ┌───────────────────────┐ → staging/{upload_id}/
                          │ package_processor     │ → DDB status=pending_review
                          │ Lambda                │ → SES email "New submission"
                          │                       │ → DLQ on failure → CW alarm
                          └───────────────────────┘
                                     │ admin promote
                                     ▼
                          ┌───────────────────────┐ → games/{game_id}/
                          │ admin_handler Lambda  │ → DDB status=published
                          │ (promote endpoint)    │ → catalog.json regen
                          │                       │ → CF invalidate
                          │                       │ → SES email "Published"
                          └───────────────────────┘
                                     │
                                     ▼
                          ┌───────────────────────┐
                          │ CloudFront            │ Portfolio + /games/* + /staging/* + /catalog/*
                          │ (strict CSP / games   │ Strict headers on portfolio
                          │  CSP / OAC)           │ Permissive CSP on /games and /staging
                          └───────────────────────┘
```

## Codebase layout

```
.checkov.yml                    Documented skip list (each one has a reason).
.tflint.hcl                     tflint config (terraform + aws rulesets).
Makefile                        `make help` lists targets.
docs/                           architecture, security, cost, upload-pipeline, local-dev, mvp-milestone, future.
docs/handoff.md                 This file.
schemas/manifest.schema.json    JSON Schema 2020-12, enforced by package_processor.
scripts/build-lambda.sh         Vendors jsonschema into the package_processor zip (Python 3.13, manylinux2014_x86_64).
scripts/create-sample-game-zip.sh
lambdas/
  package_processor/            Validation + staging deploy + admin notification.
  request_upload_url/            Issues presigned PUT URLs scoped to user_sub.
  my_uploads/                   Returns the caller's own submissions.
  admin_handler/                List/promote/reject. Checks cognito:groups claim.
frontend/public/
  index.html, app.js, styles.css   Portfolio catalog rendering.
  auth.js                          Shared OAuth + JWT + apiCall + bootstrapPage + escapeHtml.
  upload/, my-uploads/, admin/     One index.html + one page-specific JS each.
  config.js                        Terraform-generated runtime config (api endpoint, cognito IDs).
terraform/
  envs/bootstrap/                One-time state bucket + lock table.
  envs/prod/                     Real env. terraform.tfvars holds the actual values (gitignored).
  modules/
    storage/                     Uploads bucket + site bucket. Versioning, encryption, access logging.
    catalog/                     DynamoDB games table.
    cdn/                         CloudFront, OAC, URI rewrite, response-headers policies, behaviors.
    certificate/                 ACM in us-east-1 (only when enable_custom_domain=true).
    dns-records/                 Route53 aliases (gated).
    lambda-pipeline/             package_processor Lambda + frontend deploy (this couples two concerns; see M2c punch list).
    observability/               CloudTrail + audit bucket + SNS alarm topic + email subscription.
    auth/                        Cognito User Pool, Hosted UI domain, web client, admins group.
    email/                       SES sender identity (sandbox).
    api/                         HTTP API + JWT authorizer + stage + access logs. Calls lambda-endpoint x3.
    lambda-endpoint/             Reusable Lambda + IAM + route(s) + integration + permission. NEW in M2c-1.
```

## Local development quick reference

```bash
# Tests (each Lambda suite runs in its own pytest session — conftest.py module collision)
make test

# Lint (terraform fmt + tflint + checkov)
make lint

# Init / plan / apply
make init    # uses terraform/envs/prod/backend.hcl (gitignored)
make plan
make apply

# Bootstrap (one-time, already done for this account)
make bootstrap-init
make bootstrap-apply

# Sample upload via legacy ops path (lands in staging, needs admin promote)
make sample-upload
```

The local Python is 3.14; the Lambda runtime is python3.13. The build script passes `--python-version 3.13 --platform manylinux2014_x86_64 --only-binary=:all:` so wheels match the runtime regardless of local Python.

## How to authenticate as the admin for CLI testing

```bash
export AWS_PROFILE=AdministratorAccess-304119515519

# Get an admin-claim JWT (USER_PASSWORD_AUTH is enabled on the Cognito client)
JWT=$(aws cognito-idp admin-initiate-auth \
  --user-pool-id us-east-1_fR0acrCD0 \
  --client-id 4hnb4lo6dtr3uvpci9av4dvslj \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters 'USERNAME=lazare@herzi.ai,PASSWORD=YOUR_PASSWORD' \
  --query AuthenticationResult.IdToken --output text)

# Use it
curl -H "Authorization: Bearer $JWT" \
  https://zmqz8mh54d.execute-api.us-east-1.amazonaws.com/admin/pending | jq .
```

## What's next (M2c punch list, in priority order)

These were flagged by the simplify-skill pass but explicitly deferred. Each one has a reason.

1. **Shared Python helpers** in `lambdas/_common/` — `_decimal_default`, `_response`, `_filter_fields` are currently triplicated across three Lambdas. Needs a build-step change for both the `package_processor` (uses `build-lambda.sh`) and the API Lambdas (use raw `archive_file` via the `lambda-endpoint` submodule). Probably teach `lambda-endpoint` to optionally include a shared dir; or build a tiny Lambda layer.
2. **`var.alarm_email` is overloaded** as SNS alarm subscriber, SES sender, AND admin recipient. Rename to a separate `notification_email` (SES sender + admin) and keep `alarm_email` for SNS. Defaulting one to the other keeps the "just me" UX.
3. **Decide on `LEGACY_KEY_RE`** in `package_processor/handler.py`. Currently any `incoming/<file>.zip` (without user_sub) is accepted, lands in staging without a `source_user_sub`. After M2b the only producer is the presigned URL flow. Either delete the regex (and update `make sample-upload` to go through the API) or commit ("ops uploads = trusted, tag with `source_user_sub='ops'`").
4. **Lambda authorizer for group check.** `admin_handler._is_admin` currently parses the `cognito:groups` claim as a stringified array (`"[admins]"` or `"[admins,other]"`). API Gateway HTTP API JWT authorizers can assert specific scopes/claims at the edge; a small Lambda authorizer could parse once and emit a clean context, removing per-request parsing and the format-coupling risk.
5. **Parallel S3 puts/copies** via `concurrent.futures.ThreadPoolExecutor` in `package_processor.upload_package_files` (serial uploads from zip to staging) and `admin_handler._copy_prefix` (serial copies from staging to games). For a typical 50-file game, this is ~10× speedup. boto3 clients are thread-safe.
6. **Extract `frontend` module** out of `lambda-pipeline`. Currently the lambda-pipeline module owns BOTH the package_processor Lambda AND the static frontend deploy (`local.frontend_files`, `aws_s3_object.frontend`). Two unrelated concerns. Will bend back as soon as JS bundling / fingerprinting / per-page cache rules show up.
7. **`config.js` via `templatefile()`** with a `.tmpl` source instead of an inline heredoc in `terraform/envs/prod/main.tf`.

## Skipped findings (from the simplify pass — don't redo)

These were considered and intentionally NOT done:

- **Single inline-IAM-condition support** in `lambda-endpoint` — already done via `optional()` typed nested objects.
- **Page-script duplication** — already cleaned up in M2b's simplify pass (`bootstrapPage` + `escapeHtml` in auth.js).
- **DLQ for synchronous API Lambdas** (Checkov CKV_AWS_116) — inline `checkov:skip` in `lambda-endpoint` since DLQs only fire for async invocations; API Gateway returns the error synchronously.
- **KMS CMK for S3 / DDB / SNS / SQS / CloudWatch Logs / Lambda env vars** (CKV_AWS_145, 119, 158, 173) — using AWS-managed AES256 by design, documented in `.checkov.yml`.
- **WAF / cross-region replication / geo restriction / origin failover** — documented future work in `.checkov.yml`.
- **Lambda in VPC** — Lambda only calls S3/DDB/CloudFront/SQS/SES; VPC adds NAT cost without security benefit for this workload.

## Things that bit during deploy (so they don't bite again)

1. **IAM role name length 64-char limit.** With `name_prefix = ${project}-${env}-${account_id}` (43 chars), function name suffix `-package-processor` (18) + `-role` (5) = 66. **Fixed** by shortening to `-processor` (10) and `-admin`/`-presign`/`-my-uploads` for the API Lambdas. Watch this for any new resource name.
2. **`count` evaluated at plan time.** `count = var.access_logs_bucket == "" ? 0 : 1` failed because `audit_bucket_id` is "known after apply." Replaced with a separate `enable_access_logging` boolean.
3. **jsonschema 4.26 → referencing 0.37 uses Python 3.13-only `TypeVar(default=...)` syntax.** Cost us a deploy cycle — Lambda runtime was python3.12. **Now on python3.13**, build script targets `--python-version 3.13`.
4. **Build hash must include the build script itself**, not just source files. Without this, changing `build-lambda.sh` doesn't trigger a Lambda rebuild.
5. **Decimal from existing DDB items breaks json.dumps** in `to_dynamodb_item`. Fixed by passing `default=decimal_default` to the inner `json.dumps`.
6. **`game.get(key) not in {None, ""}`** fails with `TypeError: unhashable type: 'list'` when value is a list. Use a tuple `(None, "")` instead of a set.
7. **SSO tokens expire** mid-session. Re-run `aws sso login --profile AdministratorAccess-304119515519` when terraform suddenly fails on backend access.
8. **Lambda permission `statement_id` is a forced_new attribute.** Changing it (e.g., during the M2c-1 refactor) destroys + recreates the permission. Brief window (~1s) of API Gateway → Lambda denial.

## Where to read next

Open these in order for a 10-minute deep dive:
1. [README.md](../README.md) — project overview.
2. [docs/architecture.md](architecture.md) — design decisions and request flow.
3. [docs/security.md](security.md) — what's in place vs. still to add.
4. [terraform/envs/prod/main.tf](../terraform/envs/prod/main.tf) — top-level module wiring.
5. [lambdas/package_processor/handler.py](../lambdas/package_processor/handler.py) — core pipeline logic.
6. [lambdas/admin_handler/handler.py](../lambdas/admin_handler/handler.py) — promote/reject flow.
7. [terraform/modules/lambda-endpoint/main.tf](../terraform/modules/lambda-endpoint/main.tf) — the M2c-1 reusable abstraction.

## How to bring a fresh chat up to speed in one paragraph

> I'm building a serverless AWS platform for AI-generated HTML5 arcade games. Terraform-managed. Live in account 304119515519, us-east-1. We're past the foundation (P0 schema validation, P1 security headers + CloudTrail + DLQ + alarms, P2 tflint/checkov/PR-comment, M2a Cognito + presigned upload API, M2b manual gate + admin promote/reject + SPA + SES) and just finished M2c-1 (extracted the `lambda-endpoint` Terraform submodule to dedupe API Lambda boilerplate). Working tree is clean on commit `55ad2fe`. Read `docs/handoff.md` first.
