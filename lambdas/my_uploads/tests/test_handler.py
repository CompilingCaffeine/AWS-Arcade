import json
from decimal import Decimal

import pytest

import handler

VALID_SUB = "12345678-1234-1234-1234-123456789abc"

VALID_EVENT = {
    "requestContext": {
        "authorizer": {"jwt": {"claims": {"sub": VALID_SUB, "email": "u@example.com"}}}
    }
}


class _FakePaginator:
    def __init__(self, pages):
        self._pages = pages
        self.kwargs = None

    def paginate(self, **kwargs):
        self.kwargs = kwargs
        return iter(self._pages)


class _FakeMeta:
    def __init__(self, paginator):
        self.client = _FakeClient(paginator)


class _FakeClient:
    def __init__(self, paginator):
        self._paginator = paginator

    def get_paginator(self, _name):
        return self._paginator


class _FakeTable:
    def __init__(self, paginator):
        self.meta = _FakeMeta(paginator)


def _install_table(monkeypatch, pages):
    paginator = _FakePaginator(pages)
    table = _FakeTable(paginator)
    monkeypatch.setattr(handler.dynamodb, "Table", lambda _name: table)
    return paginator


def test_returns_filtered_items_sorted_by_updated_at(monkeypatch):
    items = [
        {"game_id": "old", "title": "Old", "status": "published", "updated_at": Decimal(100), "url_path": "/games/old/"},
        {"game_id": "new", "title": "New", "status": "pending_review", "updated_at": Decimal(200), "staging_url_path": "/staging/abc/"},
    ]
    paginator = _install_table(monkeypatch, [{"Items": items}])

    response = handler.handler(VALID_EVENT, None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert [it["game_id"] for it in body["items"]] == ["new", "old"]


def test_filter_uses_source_user_sub(monkeypatch):
    paginator = _install_table(monkeypatch, [{"Items": []}])
    handler.handler(VALID_EVENT, None)
    assert paginator.kwargs is not None
    assert "FilterExpression" in paginator.kwargs


def test_no_claims_returns_401():
    response = handler.handler({}, None)
    assert response["statusCode"] == 401


@pytest.mark.parametrize("bad_sub", ["", "not-a-uuid", "ZZZZ-aaaa-bbbb-cccc-1234567890ab"])
def test_invalid_sub_returns_401(bad_sub):
    event = {
        "requestContext": {"authorizer": {"jwt": {"claims": {"sub": bad_sub}}}},
    }
    response = handler.handler(event, None)
    assert response["statusCode"] == 401


def test_public_record_drops_empty():
    record = handler._public_record(
        {"game_id": "x", "title": "T", "description": "", "url_path": "/games/x/", "irrelevant": "drop me"}
    )
    assert record == {"game_id": "x", "title": "T", "url_path": "/games/x/"}
