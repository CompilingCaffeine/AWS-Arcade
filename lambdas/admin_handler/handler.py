import json
import logging
import mimetypes
import os
import time
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
cloudfront = boto3.client("cloudfront")
ses = boto3.client("ses")

SITE_BUCKET = os.environ["SITE_BUCKET"]
CATALOG_TABLE = os.environ["CATALOG_TABLE"]
SUBMISSIONS_TABLE = os.environ["SUBMISSIONS_TABLE"]
CLOUDFRONT_DISTRIBUTION_ID = os.environ["CLOUDFRONT_DISTRIBUTION_ID"]
SENDER_EMAIL = os.getenv("SENDER_EMAIL", "")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "")
PORTFOLIO_HOSTNAME = os.getenv("PORTFOLIO_HOSTNAME", "")

ADMIN_GROUP = "admins"

PUBLIC_CATALOG_FIELDS = [
    "game_id",
    "title",
    "description",
    "version",
    "author",
    "tags",
    "controls",
    "url_path",
    "thumbnail_url",
    "updated_at",
    "created_at",
]

GAME_FIELDS_FROM_SUBMISSION = [
    "title",
    "description",
    "version",
    "entrypoint",
    "author",
    "tags",
    "controls",
    "url_path",
    "thumbnail_url",
]

PUBLIC_REVIEW_FIELDS = [
    "upload_id",
    "game_id",
    "title",
    "description",
    "version",
    "author",
    "tags",
    "controls",
    "status",
    "url_path",
    "thumbnail_url",
    "staging_url_path",
    "staging_thumbnail_url",
    "source_user_sub",
    "reject_reason",
    "created_at",
    "updated_at",
]


def handler(event, _context):
    request_context = event.get("requestContext") or {}

    try:
        claims = request_context["authorizer"]["jwt"]["claims"]
    except (KeyError, TypeError):
        return _response(401, {"error": "no_jwt_claims"})

    if not _is_admin(claims):
        return _response(403, {"error": "not_admin"})

    route = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}
    upload_id = path_params.get("upload_id")

    try:
        if route == "GET /admin/pending":
            return _list_pending()
        if route == "POST /admin/submissions/{upload_id}/promote" and upload_id:
            return _promote(upload_id)
        if route == "POST /admin/submissions/{upload_id}/reject" and upload_id:
            body = json.loads(event.get("body") or "{}")
            reason = (body.get("reason") or "").strip()
            return _reject(upload_id, reason)
    except ClientError:
        LOG.exception("AWS error handling %s", route)
        return _response(500, {"error": "internal"})

    return _response(404, {"error": "not_found"})


def _is_admin(claims):
    raw = claims.get("cognito:groups", "")
    if not raw:
        return False
    # API Gateway HTTP API serializes array claims as "[group1 group2]".
    cleaned = str(raw).strip("[]")
    groups = [g.strip() for g in cleaned.replace(",", " ").split()]
    return ADMIN_GROUP in groups


def _list_pending():
    submissions = dynamodb.Table(SUBMISSIONS_TABLE)
    paginator = submissions.meta.client.get_paginator("scan")
    items = []
    for page in paginator.paginate(
        TableName=SUBMISSIONS_TABLE,
        FilterExpression=Attr("status").eq("pending_review"),
    ):
        for raw in page.get("Items", []):
            items.append(_filter_fields(_from_dynamodb(raw), PUBLIC_REVIEW_FIELDS))
    items.sort(key=lambda item: item.get("updated_at", 0), reverse=True)
    return _response(200, {"items": items})


def _promote(upload_id):
    submissions = dynamodb.Table(SUBMISSIONS_TABLE)
    games = dynamodb.Table(CATALOG_TABLE)

    submission = submissions.get_item(Key={"upload_id": upload_id}).get("Item")
    if not submission:
        return _response(404, {"error": "submission_not_found"})

    submission = _from_dynamodb(submission)
    if submission.get("status") != "pending_review":
        return _response(409, {"error": "not_pending", "current_status": submission.get("status")})

    game_id = submission["game_id"]
    existing_game = games.get_item(Key={"game_id": game_id}).get("Item")
    existing_game = _from_dynamodb(existing_game) if existing_game else None

    if existing_game and existing_game.get("source_user_sub") != submission.get("source_user_sub"):
        return _response(
            409,
            {
                "error": "ownership_conflict",
                "game_id": game_id,
                "owned_by": existing_game.get("source_user_sub"),
                "submitted_by": submission.get("source_user_sub"),
            },
        )

    source_prefix = f"staging/{upload_id}/"
    target_prefix = f"games/{game_id}/"

    _delete_prefix(SITE_BUCKET, target_prefix)
    keys_copied = _copy_prefix(SITE_BUCKET, source_prefix, SITE_BUCKET, target_prefix)
    _delete_prefix(SITE_BUCKET, source_prefix)

    now = int(time.time())
    game_item = {key: submission[key] for key in GAME_FIELDS_FROM_SUBMISSION if submission.get(key) not in (None, "")}
    game_item["game_id"] = game_id
    game_item["source_user_sub"] = submission.get("source_user_sub", "")
    game_item["current_upload_id"] = upload_id
    game_item["created_at"] = existing_game.get("created_at", now) if existing_game else now
    game_item["updated_at"] = now
    games.put_item(Item=_to_dynamodb(game_item))

    submission["status"] = "promoted"
    submission["promoted_at"] = now
    submission["updated_at"] = now
    submission.pop("reject_reason", None)
    submissions.put_item(Item=_to_dynamodb(submission))

    _write_catalog_json()
    _invalidate_paths(
        [
            f"/games/{game_id}/*",
            f"/games/{game_id}/",
            f"/staging/{upload_id}/*",
            "/catalog/catalog.json",
            "/index.html",
        ]
    )
    _notify_uploader(
        subject=f"[Herzi Arcade] Published: {game_item['title']}",
        body=(
            f"Your submission '{game_item['title']}' has been promoted to the live catalog.\n\n"
            f"Live URL: https://{PORTFOLIO_HOSTNAME}{game_item['url_path']}\n"
        ),
    )

    return _response(
        200,
        {
            "upload_id": upload_id,
            "game_id": game_id,
            "status": "promoted",
            "url_path": game_item["url_path"],
            "files_copied": keys_copied,
        },
    )


def _reject(upload_id, reason):
    submissions = dynamodb.Table(SUBMISSIONS_TABLE)
    submission = submissions.get_item(Key={"upload_id": upload_id}).get("Item")
    if not submission:
        return _response(404, {"error": "submission_not_found"})

    submission = _from_dynamodb(submission)
    if submission.get("status") != "pending_review":
        return _response(409, {"error": "not_pending", "current_status": submission.get("status")})

    staging_prefix = f"staging/{upload_id}/"
    _delete_prefix(SITE_BUCKET, staging_prefix)

    now = int(time.time())
    submission["status"] = "rejected"
    submission["updated_at"] = now
    if reason:
        submission["reject_reason"] = reason
    submissions.put_item(Item=_to_dynamodb(submission))

    _invalidate_paths([f"/staging/{upload_id}/*"])
    _notify_uploader(
        subject=f"[Herzi Arcade] Submission rejected: {submission['title']}",
        body=(
            f"Your submission '{submission['title']}' was not accepted.\n\n"
            + (f"Reason: {reason}\n" if reason else "")
        ),
    )

    return _response(200, {"upload_id": upload_id, "game_id": submission.get("game_id"), "status": "rejected"})


def _copy_prefix(source_bucket, source_prefix, target_bucket, target_prefix):
    paginator = s3.get_paginator("list_objects_v2")
    copied = 0
    for page in paginator.paginate(Bucket=source_bucket, Prefix=source_prefix):
        for obj in page.get("Contents", []):
            source_key = obj["Key"]
            tail = source_key[len(source_prefix):]
            target_key = f"{target_prefix}{tail}"
            content_type = (
                mimetypes.guess_type(target_key)[0] or "application/octet-stream"
            )
            s3.copy_object(
                Bucket=target_bucket,
                Key=target_key,
                CopySource={"Bucket": source_bucket, "Key": source_key},
                MetadataDirective="REPLACE",
                ContentType=content_type,
                CacheControl=_cache_control_for(target_key),
            )
            copied += 1
    return copied


def _delete_prefix(bucket, prefix):
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects = [{"Key": item["Key"]} for item in page.get("Contents", [])]
        if objects:
            s3.delete_objects(Bucket=bucket, Delete={"Objects": objects})


def _cache_control_for(key):
    ext = os.path.splitext(key)[1].lower()
    if ext == ".html":
        return "public,max-age=60"
    if ext == ".json":
        return "public,max-age=300"
    return "public,max-age=3600"


def _write_catalog_json():
    games = dynamodb.Table(CATALOG_TABLE)
    paginator = games.meta.client.get_paginator("scan")
    items = []
    for page in paginator.paginate(TableName=CATALOG_TABLE):
        for raw in page.get("Items", []):
            items.append(_filter_fields(_from_dynamodb(raw), PUBLIC_CATALOG_FIELDS))
    items.sort(key=lambda g: g.get("title", "").lower())
    catalog = {"generated_at": int(time.time()), "games": items}
    s3.put_object(
        Bucket=SITE_BUCKET,
        Key="catalog/catalog.json",
        Body=json.dumps(catalog, separators=(",", ":"), ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
        CacheControl="public,max-age=30",
    )


def _invalidate_paths(paths):
    cloudfront.create_invalidation(
        DistributionId=CLOUDFRONT_DISTRIBUTION_ID,
        InvalidationBatch={
            "CallerReference": f"admin-{int(time.time())}",
            "Paths": {"Quantity": len(paths), "Items": paths},
        },
    )


def _notify_uploader(subject, body):
    if not (SENDER_EMAIL and ADMIN_EMAIL):
        LOG.info("Skipping uploader notification: SENDER_EMAIL or ADMIN_EMAIL not configured")
        return
    try:
        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={"ToAddresses": [ADMIN_EMAIL]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": body}},
            },
        )
    except ClientError:
        LOG.exception("Failed to send uploader notification")


def _filter_fields(item, fields):
    return {key: item[key] for key in fields if item.get(key) not in (None, "")}


def _from_dynamodb(value):
    return json.loads(json.dumps(value, default=_decimal_default))


def _to_dynamodb(value):
    return json.loads(
        json.dumps(value, default=_decimal_default),
        parse_float=Decimal,
    )


def _decimal_default(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    raise TypeError


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
