import json

import pytest

import handler

VALID_SUB = "12345678-1234-1234-1234-123456789abc"

VALID_EVENT = {
    "requestContext": {
        "authorizer": {
            "jwt": {
                "claims": {"sub": VALID_SUB, "email": "test@example.com"},
            }
        }
    }
}


def _stub_presign(*_args, **_kwargs):
    return "https://example.com/presigned"


def test_returns_presigned_url(monkeypatch):
    monkeypatch.setattr(handler.s3, "generate_presigned_url", _stub_presign)
    response = handler.handler(VALID_EVENT, None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["upload_url"] == "https://example.com/presigned"
    assert body["key"].startswith(f"incoming/{VALID_SUB}/")
    assert body["key"].endswith(".zip")
    assert body["expires_in"] == 900
    assert body["content_type"] == "application/zip"


def test_key_uses_uuid(monkeypatch):
    monkeypatch.setattr(handler.s3, "generate_presigned_url", _stub_presign)
    r1 = json.loads(handler.handler(VALID_EVENT, None)["body"])
    r2 = json.loads(handler.handler(VALID_EVENT, None)["body"])
    assert r1["key"] != r2["key"]


def test_no_jwt_claims():
    response = handler.handler({}, None)
    assert response["statusCode"] == 401
    assert json.loads(response["body"])["error"] == "no_jwt_claims"


def test_missing_request_context():
    response = handler.handler({"requestContext": None}, None)
    assert response["statusCode"] == 401


@pytest.mark.parametrize(
    "bad_sub",
    [
        "not-a-uuid",
        "12345678123412341234123456789abc",  # no hyphens
        "ZZZZZZZZ-1234-1234-1234-123456789abc",  # non-hex
        "",
    ],
)
def test_invalid_sub(bad_sub, monkeypatch):
    monkeypatch.setattr(handler.s3, "generate_presigned_url", _stub_presign)
    event = {
        "requestContext": {
            "authorizer": {"jwt": {"claims": {"sub": bad_sub}}},
        }
    }
    response = handler.handler(event, None)
    assert response["statusCode"] == 401
    assert json.loads(response["body"])["error"] == "invalid_sub"


def test_presign_failure_returns_500(monkeypatch):
    def boom(*_a, **_kw):
        raise RuntimeError("simulated failure")

    monkeypatch.setattr(handler.s3, "generate_presigned_url", boom)
    response = handler.handler(VALID_EVENT, None)
    assert response["statusCode"] == 500
    assert json.loads(response["body"])["error"] == "internal"
