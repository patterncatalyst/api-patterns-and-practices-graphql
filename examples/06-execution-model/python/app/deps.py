"""Ch6 The execution model - FastAPI dependencies.

``GraphQLRouter(schema, context_getter=get_context)`` calls ``get_context`` once
per request and passes the result to every resolver as ``info.context``. FastAPI
resolves ``get_context``'s own dependencies first, so the process-wide call log
arrives through ``Depends(get_calls)``.
"""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Request

from app.context import TrackingContext
from app.sources import (
    BookingSource,
    DeliverySource,
    LocationSource,
    RoutingSource,
    SourceCalls,
    VoyageSource,
)


def get_calls(request: Request) -> SourceCalls:
    """The process-wide call log, created in the application's lifespan."""
    return request.app.state.calls


def get_context(calls: Annotated[SourceCalls, Depends(get_calls)]) -> TrackingContext:
    request_id = str(uuid.uuid4())
    return TrackingContext(
        request_id,
        BookingSource(calls, request_id),
        RoutingSource(calls, request_id),
        VoyageSource(calls, request_id),
        LocationSource(calls, request_id),
        DeliverySource(calls, request_id),
    )
