import json
import logging
import os
import re
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

dynamodb = boto3.resource("dynamodb")

SUBMISSIONS_TABLE = os.environ["SUBMISSIONS_TABLE"]

SUB_RE = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")

PUBLIC_FIELDS = [
    "game_id",
    "title",
    "description",
    "version",
    "author",
    "tags",
    "controls",
    "status",
    "url_path",
    "staging_url_path",
    "thumbnail_url",
    "staging_thumbnail_url",
    "upload_id",
    "created_at",
    "updated_at",
    "reject_reason",
]


def handler(event, _context):
    request_context = event.get("requestContext") or {}

    try:
        claims = request_context["authorizer"]["jwt"]["claims"]
    except (KeyError, TypeError):
        return _response(401, {"error": "no_jwt_claims"})

    user_sub = claims.get("sub", "")
    if not SUB_RE.match(user_sub):
        return _response(401, {"error": "invalid_sub"})

    table = dynamodb.Table(SUBMISSIONS_TABLE)
    paginator = table.meta.client.get_paginator("scan")
    items = []

    try:
        for page in paginator.paginate(
            TableName=SUBMISSIONS_TABLE,
            FilterExpression=Attr("source_user_sub").eq(user_sub),
        ):
            for raw in page.get("Items", []):
                items.append(_public_record(_from_dynamodb(raw)))
    except Exception:
        LOG.exception("Failed scanning catalog for user %s", user_sub)
        return _response(500, {"error": "internal"})

    items.sort(key=lambda item: item.get("updated_at", 0), reverse=True)
    return _response(200, {"items": items})


def _public_record(item):
    return {key: item[key] for key in PUBLIC_FIELDS if item.get(key) not in (None, "")}


def _from_dynamodb(value):
    return json.loads(json.dumps(value, default=_decimal_default))


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
