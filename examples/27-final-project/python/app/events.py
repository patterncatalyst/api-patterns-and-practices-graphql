"""Ch21 Real-time - the plain SSE event feed, with the authorization of Chapter 18 (Chapter 27).

``GET /events/cargos/{trackingId}`` is a server-sent event stream and not a
GraphQL operation: its payload is fixed, so there is no selection. Each event
carries ``id: <evt id>``, ``event: handled`` and a JSON ``data`` field. A browser
``EventSource`` that loses the connection reconnects by itself and sends the last
id it saw as ``Last-Event-ID``; the feed answers by replaying the cargo's events
registered after that id and then continuing live (``HandlingStore.watch``).

FastAPI serves it with ``EventSourceResponse`` and ``ServerSentEvent``: the
route is an async generator, and the framework writes the stream, the headers
and the keep-alive comments.
"""
from __future__ import annotations

from collections.abc import AsyncIterator
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.sse import EventSourceResponse, ServerSentEvent
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

from app import data
from app.access import visible
from app.auth import Identity
from app.deps import get_identity, get_store
from app.handling import HandlingRecord, HandlingStore

router = APIRouter(tags=["events"])


class Handled(BaseModel):
    """The ``data`` of a ``handled`` event: the event as the handling service recorded it."""

    model_config = ConfigDict(alias_generator=to_camel, validate_by_name=True, serialize_by_alias=True)

    id: str
    tracking_id: str
    type: str
    location: str
    completion_time: datetime

    @classmethod
    def of(cls, record: HandlingRecord) -> Handled:
        return cls(
            id=record.id,
            tracking_id=record.tracking_id,
            type=record.type.value,
            location=record.un_locode,
            completion_time=record.completion_time,
        )


def _sequence(event_id: str | None) -> int | None:
    """The number in ``evt_<n>``; ``None`` for no header or an id this feed did not issue."""
    prefix, _, number = (event_id or "").partition("_")
    return int(number) if prefix == "evt" and number.isdigit() else None


def may_watch(tracking_id: str, identity: Annotated[Identity | None, Depends(get_identity)]) -> None:
    """The rules of ``Subscription.cargoHandled`` (Chapter 18), checked before the stream
    starts: a signed-in caller (401 otherwise) who may see the cargo (403 otherwise)."""
    if identity is None:
        raise HTTPException(401, "authentication required", headers={"WWW-Authenticate": "Bearer"})
    if not visible(identity, data.OWNERS.get(tracking_id)):
        raise HTTPException(403, "not permitted to watch this cargo")


@router.get(
    "/events/cargos/{tracking_id}", response_class=EventSourceResponse, dependencies=[Depends(may_watch)]
)
async def cargo_events(
    tracking_id: str,
    store: Annotated[HandlingStore, Depends(get_store)],
    last_event_id: Annotated[str | None, Header()] = None,
) -> AsyncIterator[ServerSentEvent]:
    async for record in store.watch(tracking_id, "sse", after=_sequence(last_event_id)):
        yield ServerSentEvent(data=Handled.of(record), event="handled", id=record.id)
