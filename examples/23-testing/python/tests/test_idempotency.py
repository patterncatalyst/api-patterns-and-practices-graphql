"""Retrying a registration with the same idempotency key writes one event."""
import httpx
import pytest

from app.sources import SourceCalls

from support import Documents, post

pytestmark = pytest.mark.anyio

REGISTRATION = {
    "trackingId": "DEF456",
    "type": "CUSTOMS",
    "location": "NLRTM",
    "completionTime": "2026-10-09T16:00:00Z",
    "idempotencyKey": "ch23-test-d1",
}


async def test_replaying_a_registration_returns_the_same_event_and_writes_once(
    app_client: httpx.AsyncClient, calls: SourceCalls, documents: Documents
) -> None:
    document = documents.read("register-handling")

    first = await post(app_client, document, {"input": REGISTRATION})
    second = await post(app_client, document, {"input": REGISTRATION})

    first_id = first["data"]["registerHandlingEvent"]["handlingEvent"]["id"]
    assert second["data"]["registerHandlingEvent"]["handlingEvent"]["id"] == first_id
    writes = [call for call in calls.snapshot() if (call.source, call.op) == ("handling", "appendEvent")]
    assert len(writes) == 1
