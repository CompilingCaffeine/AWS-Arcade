import json
import logging
import mimetypes
import os
import posixpath
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

SITE_BUCKET = os.environ["SITE_BUCKET"]
CATALOG_TABLE = os.environ["CATALOG_TABLE"]
CLOUDFRONT_DISTRIBUTION_ID = os.environ["CLOUDFRONT_DISTRIBUTION_ID"]
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


class PackageValidationError(Exception):
    pass


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

    with tempfile.TemporaryDirectory() as tmpdir:
        zip_path = os.path.join(tmpdir, "game.zip")
        download_zip(bucket, key, zip_path)
        package = inspect_package(zip_path)
        manifest = package["manifest"]
        game_id = manifest["id"]
        deploy_prefix = f"games/{game_id}/"

        delete_prefix(SITE_BUCKET, deploy_prefix)
        upload_package_files(zip_path, package["files"], deploy_prefix)
        item = upsert_catalog_item(manifest, bucket, key, deploy_prefix)
        write_catalog_json()
        create_invalidation(game_id)

    LOG.info("Published game %s from s3://%s/%s", game_id, bucket, key)
    return {"bucket": bucket, "key": key, "status": "published", "game_id": game_id}


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


def upsert_catalog_item(manifest, source_bucket, source_key, deploy_prefix):
    now = int(time.time())
    game_id = manifest["id"]
    url_path = f"/{deploy_prefix}"
    thumbnail = manifest.get("thumbnail")
    item = {
        "game_id": game_id,
        "title": manifest["title"],
        "description": manifest.get("description", ""),
        "version": manifest["version"],
        "entrypoint": manifest.get("entrypoint", "index.html"),
        "author": manifest.get("author", ""),
        "tags": manifest.get("tags", []),
        "controls": manifest.get("controls", []),
        "url_path": url_path,
        "thumbnail_url": f"{url_path}{thumbnail}" if thumbnail else "",
        "source_bucket": source_bucket,
        "source_key": source_key,
        "updated_at": now,
        "status": "published",
    }

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
    return json.loads(json.dumps(value), parse_float=Decimal)


def from_dynamodb_item(value):
    return json.loads(json.dumps(value, default=decimal_default))


def decimal_default(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    raise TypeError


def write_catalog_json():
    table = dynamodb.Table(CATALOG_TABLE)
    paginator = table.meta.client.get_paginator("scan")
    games = []

    for page in paginator.paginate(TableName=CATALOG_TABLE):
        for item in page.get("Items", []):
            game = from_dynamodb_item(item)
            if game.get("status") == "published":
                games.append(public_catalog_record(game))

    games.sort(key=lambda game: game.get("title", "").lower())
    catalog = {"generated_at": int(time.time()), "games": games}
    s3.put_object(
        Bucket=SITE_BUCKET,
        Key="catalog/catalog.json",
        Body=json.dumps(catalog, separators=(",", ":"), ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
        CacheControl="public,max-age=30",
    )


def public_catalog_record(game):
    allowed_keys = [
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
    return {key: game.get(key) for key in allowed_keys if game.get(key) not in {None, ""}}


def create_invalidation(game_id):
    paths = [
        f"/games/{game_id}/*",
        f"/games/{game_id}/",
        "/catalog/catalog.json",
        "/index.html",
    ]
    cloudfront.create_invalidation(
        DistributionId=CLOUDFRONT_DISTRIBUTION_ID,
        InvalidationBatch={
            "CallerReference": f"{game_id}-{int(time.time())}",
            "Paths": {"Quantity": len(paths), "Items": paths},
        },
    )
