import json
import logging
import os
import re
import uuid

import boto3

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")

UPLOAD_BUCKET = os.environ["UPLOAD_BUCKET"]
PRESIGNED_URL_TTL_SECS = int(os.environ.get("PRESIGNED_URL_TTL_SECS", "900"))
MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", str(50 * 1024 * 1024)))

SUB_RE = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")


def handler(event, _context):
    request_context = event.get("requestContext") or {}
    LOG.info("Received request: %s", json.dumps({"requestContext": request_context}))

    try:
        claims = request_context["authorizer"]["jwt"]["claims"]
    except (KeyError, TypeError):
        return _response(401, {"error": "no_jwt_claims"})

    user_sub = claims.get("sub", "")
    if not SUB_RE.match(user_sub):
        return _response(401, {"error": "invalid_sub"})

    upload_id = uuid.uuid4().hex
    key = f"incoming/{user_sub}/{upload_id}.zip"

    try:
        url = s3.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": UPLOAD_BUCKET,
                "Key": key,
                "ContentType": "application/zip",
            },
            ExpiresIn=PRESIGNED_URL_TTL_SECS,
            HttpMethod="PUT",
        )
    except Exception:
        LOG.exception("Failed to generate presigned URL for %s", key)
        return _response(500, {"error": "internal"})

    return _response(
        200,
        {
            "upload_url": url,
            "key": key,
            "expires_in": PRESIGNED_URL_TTL_SECS,
            "max_bytes": MAX_UPLOAD_BYTES,
            "content_type": "application/zip",
        },
    )


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
