"""Behaviour the schema cannot show: how many calls reach the sources."""
import httpx
import pytest

from app.sources import SourceCalls

from support import Documents, post

pytestmark = pytest.mark.anyio


async def test_fan_out_makes_six_source_calls_under_one_request_id(
    app_client: httpx.AsyncClient, calls: SourceCalls, documents: Documents
) -> None:
    await post(app_client, documents.read("fan-out"))

    log = calls.snapshot()
    assert len(log) == 6
    assert len({call.request for call in log}) == 1


async def test_fan_out_asks_each_owner_once_for_all_four_cargos(
    app_client: httpx.AsyncClient, calls: SourceCalls, documents: Documents
) -> None:
    await post(app_client, documents.read("fan-out"))

    entries = sorted(f"{call.source}.{call.op}:{call.key}" for call in calls.snapshot())
    assert entries == [
        "booking.getCargos:DEF456+STU678+VWX901+XYZ789",
        "booking.listCargos:*",
        "handling.listEventsFor:DEF456+STU678+VWX901+XYZ789",
        "location.getLocations:CNSHA+DEHAM+NLRTM+SGSIN+USNYC",
        "routing.getItineraries:DEF456+STU678+VWX901+XYZ789",
        "voyage.getVoyages:V100S+V200E+V300A",
    ]
