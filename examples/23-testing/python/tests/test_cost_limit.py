"""A request over the cost budget is refused with a stated price, before any source is called."""
import httpx
import pytest

from app.sources import SourceCalls

from support import Documents, post

pytestmark = pytest.mark.anyio


async def test_over_budget_document_is_refused_before_any_source_call(
    app_client: httpx.AsyncClient, calls: SourceCalls, documents: Documents
) -> None:
    body = await post(app_client, documents.read("load/over-budget"))

    assert body["data"] is None
    assert [error["message"] for error in body["errors"]] == ["maximum query complexity exceeded 7651 > 1000"]
    assert calls.snapshot() == [], "a refused request makes no source call"


async def test_a_page_within_the_budget_still_runs(app_client: httpx.AsyncClient) -> None:
    body = await post(app_client, "{ cargos(first: 4) { edges { node { trackingId } } } }")

    assert "errors" not in body
    assert len(body["data"]["cargos"]["edges"]) == 4
