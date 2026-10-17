"""Operation layer: the four documents Chapter 22's clients send, over the application's HTTP layer."""
import httpx
import pytest
from starlette.testclient import TestClient
from strawberry.asgi.test import GraphQLTestClient

from app.main import app

from support import Documents, post

pytestmark = pytest.mark.anyio


async def test_track_cargo_returns_the_cargo_its_places_and_its_delivery(
    app_client: httpx.AsyncClient, documents: Documents
) -> None:
    body = await post(app_client, documents.read("track-cargo"), {"id": "ABC123"})

    assert "errors" not in body
    cargo = body["data"]["cargo"]
    assert cargo["trackingId"] == "ABC123"
    assert cargo["description"] == "Palletized electronics"
    assert cargo["origin"]["name"] == "New York"
    assert cargo["destination"]["name"] == "Rotterdam"
    assert cargo["delivery"] == {"transportStatus": "ONBOARD_CARRIER", "routingStatus": "ROUTED"}


async def test_track_cargo_brief_is_a_subset_of_track_cargo(
    app_client: httpx.AsyncClient, documents: Documents
) -> None:
    body = await post(app_client, documents.read("track-cargo-brief"), {"id": "ABC123"})

    assert "errors" not in body
    assert body["data"]["cargo"] == {
        "id": "cargo_ABC123",
        "trackingId": "ABC123",
        "delivery": {"transportStatus": "ONBOARD_CARRIER"},
    }


async def test_register_handling_accepts_an_event_and_returns_no_user_errors(
    app_client: httpx.AsyncClient, documents: Documents
) -> None:
    registration = {
        "trackingId": "DEF456",
        "type": "CUSTOMS",
        "location": "NLRTM",
        "completionTime": "2026-10-09T16:00:00Z",
        "idempotencyKey": "ch23-test-operations",
    }

    body = await post(app_client, documents.read("register-handling"), {"input": registration})

    assert "errors" not in body
    payload = body["data"]["registerHandlingEvent"]
    assert payload["handlingEvent"]["id"]
    assert payload["userErrors"] == []
    assert payload["cargo"]["id"] == "cargo_DEF456"


async def test_list_cargos_returns_six_edges_and_reports_the_booking_outage_at_one_node(
    app_client: httpx.AsyncClient, documents: Documents
) -> None:
    # One cargo cannot be loaded. Strawberry fails only that key, so five
    # nodes arrive and one error is reported at the sixth.
    body = await post(app_client, documents.read("list-cargos"))

    edges = body["data"]["cargos"]["edges"]
    assert len(edges) == 6
    assert sum(edge["node"] is None for edge in edges) == 1
    assert len(body["errors"]) == 1
    assert body["errors"][0]["path"] == ["cargos", "edges", 5, "node"]
    assert body["errors"][0]["extensions"] == {"code": "SERVICE_UNAVAILABLE"}


def test_strawberrys_test_client_returns_data_and_errors_apart(documents: Documents) -> None:
    # Starlette's TestClient runs the lifespan inside its context manager.
    with TestClient(app) as http:
        response = GraphQLTestClient(http).query(
            documents.read("track-cargo-brief"), variables={"id": "ABC123"}, assert_no_errors=False
        )

    assert response.errors is None
    assert response.data["cargo"]["delivery"]["transportStatus"] == "ONBOARD_CARRIER"
