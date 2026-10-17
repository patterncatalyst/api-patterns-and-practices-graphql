"""Ch21 Real-time - the source-call log and the live subscriber counts over HTTP (lab only).

Included in the application only when ``TRACKING_DEBUG_ENDPOINTS=true``. Plain
FastAPI routers beside ``/graphql``, so they add nothing to the GraphQL schema.
The responses use camelCase keys (``startMs``, ``endMs``) so both stacks serve
the same JSON. ``/debug/subscribers`` reports, per channel (``graphql`` for
``Subscription.cargoHandled``, ``sse`` for the event feed) and tracking id, how
many subscriptions are live.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

from app.deps import get_calls, get_store
from app.handling import Channel, HandlingStore
from app.sources import SourceCalls

router = APIRouter(prefix="/debug/source-calls", tags=["debug"])
subscribers_router = APIRouter(prefix="/debug/subscribers", tags=["debug"])


class SourceCallOut(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, validate_by_name=True, from_attributes=True)

    request: str
    source: str
    op: str
    key: str
    start_ms: int
    end_ms: int


class CallLog(BaseModel):
    calls: list[SourceCallOut]


@router.get("")
def list_calls(calls: Annotated[SourceCalls, Depends(get_calls)]) -> CallLog:
    return CallLog(calls=[SourceCallOut.model_validate(c) for c in calls.snapshot()])


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def reset_calls(calls: Annotated[SourceCalls, Depends(get_calls)]) -> Response:
    calls.reset()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@subscribers_router.get("")
def list_subscribers(store: Annotated[HandlingStore, Depends(get_store)]) -> dict[Channel, dict[str, int]]:
    return store.subscriber_counts()
