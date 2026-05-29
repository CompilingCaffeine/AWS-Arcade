import json

import pytest

import handler


def _event(route, claims, game_id=None, body=None):
    return {
        "routeKey": route,
        "pathParameters": {"game_id": game_id} if game_id else None,
        "requestContext": {"authorizer": {"jwt": {"claims": claims}}},
        "body": json.dumps(body) if body is not None else None,
    }


ADMIN_CLAIMS = {"sub": "00000000-0000-0000-0000-000000000001", "cognito:groups": "[admins]"}
USER_CLAIMS = {"sub": "00000000-0000-0000-0000-000000000002", "cognito:groups": "[]"}


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
