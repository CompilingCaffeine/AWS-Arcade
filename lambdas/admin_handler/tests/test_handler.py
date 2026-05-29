import json

import pytest

import handler


def _event(route, claims, upload_id=None, body=None):
    path_params = {}
    if upload_id is not None:
        path_params["upload_id"] = upload_id
    return {
        "routeKey": route,
        "pathParameters": path_params or None,
        "requestContext": {"authorizer": {"jwt": {"claims": claims}}},
        "body": json.dumps(body) if body is not None else None,
    }


ADMIN_CLAIMS = {"sub": "00000000-0000-0000-0000-000000000001", "cognito:groups": "[admins]"}
USER_CLAIMS = {"sub": "00000000-0000-0000-0000-000000000002", "cognito:groups": "[]"}


class _FakeTable:
    def __init__(self, items=None):
        self.items = dict(items or {})
        self.put_calls = []

    def get_item(self, Key):
        key = next(iter(Key.values()))
        return {"Item": self.items[key]} if key in self.items else {}

    def put_item(self, Item):
        self.put_calls.append(Item)
        key = Item.get("upload_id") or Item.get("game_id")
        self.items[key] = Item


class _FakeDynamoDB:
    def __init__(self, tables):
        self._tables = tables

    def Table(self, name):
        return self._tables[name]


def _install_tables(monkeypatch, submissions, games):
    fake = _FakeDynamoDB({
        handler.SUBMISSIONS_TABLE: submissions,
        handler.CATALOG_TABLE: games,
    })
    monkeypatch.setattr(handler, "dynamodb", fake)


# _is_admin


@pytest.mark.parametrize(
    "groups,expected",
    [
        ("[admins]", True),
        ("[admins other]", True),
        ("[other]", False),
        ("", False),
        ("[admins,other]", True),
    ],
)
def test_is_admin_parsing(groups, expected):
    assert handler._is_admin({"cognito:groups": groups}) is expected


# Auth gating


def test_no_claims_returns_401():
    response = handler.handler({}, None)
    assert response["statusCode"] == 401


def test_non_admin_returns_403():
    response = handler.handler(_event("GET /admin/pending", USER_CLAIMS), None)
    assert response["statusCode"] == 403


def test_unknown_route_returns_404():
    response = handler.handler(_event("GET /admin/bogus", ADMIN_CLAIMS), None)
    assert response["statusCode"] == 404


# Helpers


def test_filter_fields_drops_empty_and_none():
    record = handler._filter_fields(
        {"a": "x", "b": "", "c": None, "d": "y", "e": 0}, ["a", "b", "c", "d", "e", "missing"]
    )
    assert record == {"a": "x", "d": "y", "e": 0}


def test_cache_control_html():
    assert "max-age=60" in handler._cache_control_for("staging/x/index.html")


def test_cache_control_json():
    assert "max-age=300" in handler._cache_control_for("catalog/catalog.json")


def test_cache_control_other():
    assert "max-age=3600" in handler._cache_control_for("staging/x/sprite.png")


# Promote — ownership and pre-condition guards


def test_promote_ownership_conflict_returns_409(monkeypatch):
    submissions = _FakeTable({
        "upload-A": {
            "upload_id": "upload-A",
            "game_id": "tetris",
            "status": "pending_review",
            "source_user_sub": "user-A",
            "title": "Tetris",
        }
    })
    games = _FakeTable({
        "tetris": {"game_id": "tetris", "source_user_sub": "user-B"},
    })
    _install_tables(monkeypatch, submissions, games)

    event = _event("POST /admin/submissions/{upload_id}/promote", ADMIN_CLAIMS, upload_id="upload-A")
    response = handler.handler(event, None)

    assert response["statusCode"] == 409
    body = json.loads(response["body"])
    assert body["error"] == "ownership_conflict"
    assert body["owned_by"] == "user-B"
    assert body["submitted_by"] == "user-A"
    assert submissions.put_calls == []  # submission was not mutated


def test_promote_missing_submission_returns_404(monkeypatch):
    _install_tables(monkeypatch, _FakeTable(), _FakeTable())
    event = _event("POST /admin/submissions/{upload_id}/promote", ADMIN_CLAIMS, upload_id="nope")
    response = handler.handler(event, None)
    assert response["statusCode"] == 404
    assert json.loads(response["body"])["error"] == "submission_not_found"


def test_promote_already_promoted_returns_409(monkeypatch):
    submissions = _FakeTable({
        "upload-A": {
            "upload_id": "upload-A",
            "game_id": "tetris",
            "status": "promoted",
            "source_user_sub": "user-A",
            "title": "Tetris",
        }
    })
    _install_tables(monkeypatch, submissions, _FakeTable())
    event = _event("POST /admin/submissions/{upload_id}/promote", ADMIN_CLAIMS, upload_id="upload-A")
    response = handler.handler(event, None)
    assert response["statusCode"] == 409
    assert json.loads(response["body"])["error"] == "not_pending"


def test_reject_marks_status_and_records_reason(monkeypatch):
    submissions = _FakeTable({
        "upload-A": {
            "upload_id": "upload-A",
            "game_id": "tetris",
            "status": "pending_review",
            "source_user_sub": "user-A",
            "title": "Tetris",
        }
    })
    _install_tables(monkeypatch, submissions, _FakeTable())

    # Stub out S3 / CloudFront / SES side effects since reject still calls them
    monkeypatch.setattr(handler, "_delete_prefix", lambda *_a, **_k: None)
    monkeypatch.setattr(handler, "_invalidate_paths", lambda *_a, **_k: None)
    monkeypatch.setattr(handler, "_notify_uploader", lambda *_a, **_k: None)

    event = _event(
        "POST /admin/submissions/{upload_id}/reject",
        ADMIN_CLAIMS,
        upload_id="upload-A",
        body={"reason": "broken entrypoint"},
    )
    response = handler.handler(event, None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "rejected"
    assert body["game_id"] == "tetris"
    assert submissions.items["upload-A"]["status"] == "rejected"
    assert submissions.items["upload-A"]["reject_reason"] == "broken entrypoint"
