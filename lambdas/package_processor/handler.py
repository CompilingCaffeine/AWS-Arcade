import json
import logging
import mimetypes
import os
import posixpath
import re
import tempfile
import time
import urllib.parse
import zipfile
from decimal import Decimal
from pathlib import PurePosixPath

import boto3
from botocore.exceptions import ClientError
from jsonschema import Draft202012Validator

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
cloudfront = boto3.client("cloudfront")
ses = boto3.client("ses")

SITE_BUCKET = os.environ["SITE_BUCKET"]
CATALOG_TABLE = os.environ["CATALOG_TABLE"]
CLOUDFRONT_DISTRIBUTION_ID = os.environ["CLOUDFRONT_DISTRIBUTION_ID"]
SENDER_EMAIL = os.getenv("SENDER_EMAIL", "")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "")
PORTFOLIO_HOSTNAME = os.getenv("PORTFOLIO_HOSTNAME", "")
MAX_ZIP_BYTES = int(os.getenv("MAX_ZIP_BYTES", str(50 * 1024 * 1024)))
MAX_UNCOMPRESSED_BYTES = int(os.getenv("MAX_UNCOMPRESSED_BYTES", str(150 * 1024 * 1024)))
MAX_FILE_COUNT = int(os.getenv("MAX_FILE_COUNT", "500"))

SCHEMA_PATH = os.getenv(
    "MANIFEST_SCHEMA_PATH",
    os.path.join(os.path.dirname(__file__), "manifest.schema.json"),
)
with open(SCHEMA_PATH) as _schema_file:
    MANIFEST_SCHEMA = json.load(_schema_file)
MANIFEST_VALIDATOR = Draft202012Validator(MANIFEST_SCHEMA)

ALLOWED_EXTENSIONS = {
    ".html",
    ".css",
    ".js",
    ".mjs",
    ".json",
    ".txt",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".svg",
    ".webp",
    ".ico",
    ".wav",
    ".mp3",
    ".ogg",
    ".wasm",
    ".woff",
    ".woff2",
    ".ttf",
}


USER_KEY_RE = re.compile(
    r"^incoming/"
    r"(?P<user_sub>[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/"
    r"(?P<upload_id>[a-zA-Z0-9._-]+)\.zip$"
)
LEGACY_KEY_RE = re.compile(r"^incoming/(?P<upload_id>[a-zA-Z0-9._-]+)\.zip$")


class PackageValidationError(Exception):
    pass


def parse_upload_key(key):
    """Return (user_sub, upload_id). user_sub is None for legacy ops uploads."""
    match = USER_KEY_RE.match(key)
    if match:
        return match.group("user_sub"), match.group("upload_id")
    match = LEGACY_KEY_RE.match(key)
    if match:
        return None, match.group("upload_id")
    raise PackageValidationError(f"Unexpected upload key shape: {key}")


def handler(event, _context):
    LOG.info("Received event: %s", json.dumps(event))
    results = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        results.append(process_upload(bucket, key))

    return {"results": results}


def process_upload(bucket, key):
    if not key.lower().endswith(".zip"):
        LOG.info("Skipping non-zip object s3://%s/%s", bucket, key)
        return {"bucket": bucket, "key": key, "status": "skipped"}

    user_sub, upload_id = parse_upload_key(key)

    with tempfile.TemporaryDirectory() as tmpdir:
        zip_path = os.path.join(tmpdir, "game.zip")
        download_zip(bucket, key, zip_path)
        package = inspect_package(zip_path)
        manifest = package["manifest"]
        game_id = manifest["id"]
        staging_prefix = f"staging/{upload_id}/"

        delete_prefix(SITE_BUCKET, staging_prefix)
        upload_package_files(zip_path, package["files"], staging_prefix)
        item = upsert_catalog_item(manifest, bucket, key, staging_prefix, user_sub, upload_id)
        create_staging_invalidation(upload_id)
        notify_admin_new_submission(item)

    LOG.info(
        "Staged game %s (upload_id=%s) from s3://%s/%s for review", game_id, upload_id, bucket, key
    )
    return {
        "bucket": bucket,
        "key": key,
        "status": "pending_review",
        "game_id": game_id,
        "upload_id": upload_id,
    }


def download_zip(bucket, key, zip_path):
    head = s3.head_object(Bucket=bucket, Key=key)
    size = head.get("ContentLength", 0)
    if size > MAX_ZIP_BYTES:
        raise PackageValidationError(f"ZIP is too large: {size} bytes")

    s3.download_file(bucket, key, zip_path)


def inspect_package(zip_path):
    with zipfile.ZipFile(zip_path) as archive:
        infos = [info for info in archive.infolist() if not info.is_dir()]
        if len(infos) > MAX_FILE_COUNT:
            raise PackageValidationError(f"Too many files: {len(infos)}")

        total_uncompressed = sum(info.file_size for info in infos)
        if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
            raise PackageValidationError(
                f"Package is too large after extraction: {total_uncompressed} bytes"
            )

        normalized_files = {}
        for info in infos:
            normalized_name = normalize_zip_path(info.filename)
            if normalized_name in normalized_files:
                raise PackageValidationError(f"Duplicate ZIP path: {normalized_name}")

            extension = PurePosixPath(normalized_name).suffix.lower()
            if extension not in ALLOWED_EXTENSIONS:
                raise PackageValidationError(f"Unsupported file type: {normalized_name}")
            normalized_files[normalized_name] = info

        if "manifest.json" not in normalized_files:
            raise PackageValidationError("manifest.json is required at the package root")

        manifest = json.loads(archive.read(normalized_files["manifest.json"]).decode("utf-8"))
        validate_manifest(manifest)

        entrypoint = manifest.get("entrypoint", "index.html")
        if entrypoint not in normalized_files:
            raise PackageValidationError(f"Entrypoint not found: {entrypoint}")

        thumbnail = manifest.get("thumbnail")
        if thumbnail and thumbnail not in normalized_files:
            raise PackageValidationError(f"Thumbnail not found: {thumbnail}")

        return {"manifest": manifest, "files": normalized_files}


def normalize_zip_path(filename):
    path = PurePosixPath(filename)
    if path.is_absolute() or ".." in path.parts:
        raise PackageValidationError(f"Unsafe ZIP path: {filename}")

    normalized = posixpath.normpath(str(path))
    if normalized in {".", ""} or normalized.startswith("../"):
        raise PackageValidationError(f"Unsafe ZIP path: {filename}")

    return normalized


def validate_manifest(manifest):
    errors = sorted(
        MANIFEST_VALIDATOR.iter_errors(manifest),
        key=lambda e: list(e.absolute_path),
    )
    if errors:
        formatted = "; ".join(_format_schema_error(e) for e in errors)
        raise PackageValidationError(f"Manifest invalid: {formatted}")


def _format_schema_error(error):
    path = "/".join(str(part) for part in error.absolute_path) or "<root>"
    return f"{path}: {error.message}"


def delete_prefix(bucket, prefix):
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects = [{"Key": item["Key"]} for item in page.get("Contents", [])]
        if objects:
            s3.delete_objects(Bucket=bucket, Delete={"Objects": objects})


def upload_package_files(zip_path, files, deploy_prefix):
    with zipfile.ZipFile(zip_path) as archive:
        for normalized_name, info in files.items():
            body = archive.read(info)
            destination_key = f"{deploy_prefix}{normalized_name}"
            content_type = mimetypes.guess_type(normalized_name)[0] or "application/octet-stream"
            cache_control = cache_control_for(normalized_name)
            s3.put_object(
                Bucket=SITE_BUCKET,
                Key=destination_key,
                Body=body,
                ContentType=content_type,
                CacheControl=cache_control,
            )


def cache_control_for(filename):
    extension = PurePosixPath(filename).suffix.lower()
    if extension == ".html":
        return "public,max-age=60"
    if extension == ".json":
        return "public,max-age=300"
    return "public,max-age=3600"


def upsert_catalog_item(manifest, source_bucket, source_key, staging_prefix, user_sub, upload_id):
    now = int(time.time())
    game_id = manifest["id"]
    url_path = f"/games/{game_id}/"
    staging_url_path = f"/{staging_prefix}"
    thumbnail = manifest.get("thumbnail")
    item = {
        "game_id": game_id,
        "upload_id": upload_id,
        "title": manifest["title"],
        "description": manifest.get("description", ""),
        "version": manifest["version"],
        "entrypoint": manifest.get("entrypoint", "index.html"),
        "author": manifest.get("author", ""),
        "tags": manifest.get("tags", []),
        "controls": manifest.get("controls", []),
        "url_path": url_path,
        "staging_url_path": staging_url_path,
        "thumbnail_url": f"{url_path}{thumbnail}" if thumbnail else "",
        "staging_thumbnail_url": f"{staging_url_path}{thumbnail}" if thumbnail else "",
        "source_bucket": source_bucket,
        "source_key": source_key,
        "updated_at": now,
        "status": "pending_review",
    }
    if user_sub:
        item["source_user_sub"] = user_sub

    table = dynamodb.Table(CATALOG_TABLE)
    existing_created_at = get_existing_created_at(table, game_id)
    item["created_at"] = existing_created_at or now
    table.put_item(Item=to_dynamodb_item(item))
    return item


def get_existing_created_at(table, game_id):
    try:
        response = table.get_item(Key={"game_id": game_id}, ProjectionExpression="created_at")
    except ClientError:
        LOG.exception("Unable to read existing catalog item for %s", game_id)
        return None

    return response.get("Item", {}).get("created_at")


def to_dynamodb_item(value):
    return json.loads(
        json.dumps(value, default=decimal_default),
        parse_float=Decimal,
    )


def decimal_default(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    raise TypeError


def create_staging_invalidation(upload_id):
    paths = [
        f"/staging/{upload_id}/*",
        f"/staging/{upload_id}/",
    ]
    cloudfront.create_invalidation(
        DistributionId=CLOUDFRONT_DISTRIBUTION_ID,
        InvalidationBatch={
            "CallerReference": f"stage-{upload_id}-{int(time.time())}",
            "Paths": {"Quantity": len(paths), "Items": paths},
        },
    )


def notify_admin_new_submission(item):
    if not (SENDER_EMAIL and ADMIN_EMAIL and PORTFOLIO_HOSTNAME):
        LOG.info("Skipping admin notification: sender/admin/portfolio not configured")
        return

    preview = f"https://{PORTFOLIO_HOSTNAME}{item['staging_url_path']}"
    review_url = f"https://{PORTFOLIO_HOSTNAME}/admin/"
    body = (
        f"A new game has been submitted for review.\n\n"
        f"Title: {item['title']}\n"
        f"Game ID: {item['game_id']}\n"
        f"Author: {item.get('author') or '(none)'}\n"
        f"Uploader: {item.get('source_user_sub') or '(legacy)'}\n\n"
        f"Preview: {preview}\n"
        f"Review:  {review_url}\n"
    )

    try:
        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={"ToAddresses": [ADMIN_EMAIL]},
            Message={
                "Subject": {"Data": f"[Herzi Arcade] New submission: {item['title']}"},
                "Body": {"Text": {"Data": body}},
            },
        )
    except ClientError:
        LOG.exception("Failed to send admin notification for %s", item["game_id"])
