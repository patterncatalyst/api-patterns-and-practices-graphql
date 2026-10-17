"""Ch20 Federation, cargo subgraph - FastAPI dependencies.

``GraphQLRouter(schema, context_getter=get_context)`` calls ``get_context`` once
per request and passes the result to every resolver as ``info.context``. FastAPI
resolves ``get_context``'s own dependencies first, so the process-wide call log
arrives through ``Depends(get_calls)``. The request's DataLoaders are built
here too, over the request's own sources: a loader and its cache never outlive
the request.
"""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Request

from app.context import TrackingContext
from app.loaders import Loaders
from app.sources import (
    BookingSource,
    LocationSource,
    RoutingSource,
    SourceCalls,
    VoyageSource,
)


def get_calls(request: Request) -> SourceCalls:
    """The process-wide call log, created in the application's lifespan."""
    return request.app.state.calls


def get_context(
    calls: Annotated[SourceCalls, Depends(get_calls)],
) -> TrackingContext:
    request_id = str(uuid.uuid4())
    booking = BookingSource(calls, request_id)
    routing = RoutingSource(calls, request_id)
    voyage = VoyageSource(calls, request_id)
    location = LocationSource(calls, request_id)
    return TrackingContext(
        request_id,
        booking,
        routing,
        voyage,
        location,
        Loaders.for_request(booking, routing, voyage, location),
    )
