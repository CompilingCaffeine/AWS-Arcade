import json
import zipfile
from decimal import Decimal

import pytest

import handler

VALID_MANIFEST = {
    "id": "cosmic-clicker",
    "title": "Cosmic Clicker",
    "version": "1.0.0",
    "entrypoint": "index.html",
}


def make_zip(tmp_path, files):
    zip_path = tmp_path / "test.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        for name, content in files.items():
            archive.writestr(name, content)
    return str(zip_path)


# validate_manifest


def test_validate_manifest_accepts_minimal():
    handler.validate_manifest(VALID_MANIFEST)


def test_validate_manifest_accepts_full():
    handler.validate_manifest(
        {
            **VALID_MANIFEST,
            "description": "A demo game",
            "author": "Herzi AI",
            "tags": ["arcade", "demo"],
            "thumbnail": "thumb.png",
            "controls": ["Mouse"],
        }
    )


@pytest.mark.parametrize("missing", ["id", "title", "version", "entrypoint"])
def test_validate_manifest_rejects_missing_required(missing):
    manifest = dict(VALID_MANIFEST)
    del manifest[missing]
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest(manifest)


@pytest.mark.parametrize(
    "bad_id",
    ["ab", "UPPER", "-leading", "has space", "with_underscore", "a" * 64],
)
def test_validate_manifest_rejects_bad_id(bad_id):
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest({**VALID_MANIFEST, "id": bad_id})


@pytest.mark.parametrize("bad_version", ["1.0", "1", "v1.0.0", "1.0.0-rc1"])
def test_validate_manifest_rejects_bad_version(bad_version):
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest({**VALID_MANIFEST, "version": bad_version})


def test_validate_manifest_rejects_non_html_entrypoint():
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest({**VALID_MANIFEST, "entrypoint": "main.js"})


def test_validate_manifest_rejects_unknown_field():
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest({**VALID_MANIFEST, "unknown": "x"})


def test_validate_manifest_rejects_non_array_tags():
    with pytest.raises(handler.PackageValidationError):
        handler.validate_manifest({**VALID_MANIFEST, "tags": "arcade"})


# normalize_zip_path


@pytest.mark.parametrize(
    "path",
    ["index.html", "assets/sprite.png", "a/b/c.js"],
)
def test_normalize_zip_path_accepts_relative(path):
    assert handler.normalize_zip_path(path) == path


@pytest.mark.parametrize(
    "path",
    ["/absolute.html", "../escape.html", "a/../../b.html"],
)
def test_normalize_zip_path_rejects_unsafe(path):
    with pytest.raises(handler.PackageValidationError):
        handler.normalize_zip_path(path)


# cache_control_for


def test_cache_control_html_short():
    assert handler.cache_control_for("index.html") == "public,max-age=60"


def test_cache_control_json_medium():
    assert handler.cache_control_for("data.json") == "public,max-age=300"


def test_cache_control_other_long():
    assert handler.cache_control_for("script.js") == "public,max-age=3600"


# inspect_package


def test_inspect_package_valid(tmp_path):
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps(VALID_MANIFEST),
            "index.html": "<html></html>",
        },
    )
    package = handler.inspect_package(zip_path)
    assert package["manifest"]["id"] == "cosmic-clicker"
    assert "index.html" in package["files"]
    assert "manifest.json" in package["files"]


def test_inspect_package_missing_manifest(tmp_path):
    zip_path = make_zip(tmp_path, {"index.html": "<html></html>"})
    with pytest.raises(handler.PackageValidationError, match="manifest.json"):
        handler.inspect_package(zip_path)


def test_inspect_package_missing_entrypoint(tmp_path):
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps({**VALID_MANIFEST, "entrypoint": "main.html"}),
            "index.html": "<html></html>",
        },
    )
    with pytest.raises(handler.PackageValidationError, match="Entrypoint"):
        handler.inspect_package(zip_path)


def test_inspect_package_missing_thumbnail(tmp_path):
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps({**VALID_MANIFEST, "thumbnail": "thumb.png"}),
            "index.html": "<html></html>",
        },
    )
    with pytest.raises(handler.PackageValidationError, match="Thumbnail"):
        handler.inspect_package(zip_path)


def test_inspect_package_rejects_unsupported_extension(tmp_path):
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps(VALID_MANIFEST),
            "index.html": "<html></html>",
            "evil.exe": "MZ",
        },
    )
    with pytest.raises(handler.PackageValidationError, match="Unsupported file type"):
        handler.inspect_package(zip_path)


def test_inspect_package_rejects_path_traversal(tmp_path):
    zip_path = tmp_path / "test.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.writestr("manifest.json", json.dumps(VALID_MANIFEST))
        archive.writestr("index.html", "<html></html>")
        info = zipfile.ZipInfo("../escape.html")
        archive.writestr(info, "x")
    with pytest.raises(handler.PackageValidationError, match="Unsafe ZIP path"):
        handler.inspect_package(str(zip_path))


def test_inspect_package_rejects_too_many_files(tmp_path, monkeypatch):
    monkeypatch.setattr(handler, "MAX_FILE_COUNT", 2)
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps(VALID_MANIFEST),
            "index.html": "<html></html>",
            "extra.html": "<html></html>",
        },
    )
    with pytest.raises(handler.PackageValidationError, match="Too many files"):
        handler.inspect_package(zip_path)


def test_inspect_package_rejects_oversized_uncompressed(tmp_path, monkeypatch):
    monkeypatch.setattr(handler, "MAX_UNCOMPRESSED_BYTES", 100)
    zip_path = make_zip(
        tmp_path,
        {
            "manifest.json": json.dumps(VALID_MANIFEST),
            "index.html": "x" * 200,
        },
    )
    with pytest.raises(handler.PackageValidationError, match="too large"):
        handler.inspect_package(zip_path)


# parse_upload_key


def test_parse_upload_key_user_namespaced():
    sub = "12345678-1234-1234-1234-123456789abc"
    user_sub, upload_id = handler.parse_upload_key(f"incoming/{sub}/abc123.zip")
    assert user_sub == sub
    assert upload_id == "abc123"


def test_parse_upload_key_legacy():
    user_sub, upload_id = handler.parse_upload_key("incoming/sample-game.zip")
    assert user_sub is None
    assert upload_id == "sample-game"


@pytest.mark.parametrize(
    "bad_key",
    [
        "uploads/game.zip",
        "incoming/nested/path/game.zip",
        "incoming/not-a-uuid/upload.zip",
        "incoming/12345678-1234-1234-1234-123456789abc/sub/path.zip",
    ],
)
def test_parse_upload_key_rejects_unexpected(bad_key):
    with pytest.raises(handler.PackageValidationError):
        handler.parse_upload_key(bad_key)


# to_dynamodb_item — regression tests


def test_to_dynamodb_item_round_trips_decimal_from_existing_record():
    item = {"game_id": "x", "updated_at": 1, "created_at": Decimal("1779944223")}
    result = handler.to_dynamodb_item(item)
    assert result["game_id"] == "x"
    assert result["created_at"] == Decimal("1779944223")


