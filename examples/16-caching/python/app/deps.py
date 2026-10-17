"""Ch16 Caching - FastAPI dependencies.

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

from app import data
from app.context import TrackingContext
from app.caches import SourceCaches
from app.derivation import DeliveryDerivation
from app.handling import HandlingStore
from app.loaders import Loaders
from app.sources import (
    BookingSource,
    HandlingSource,
    LocationSource,
    RoutingSource,
    SourceCalls,
    VoyageSource,
)


# Stateless and shared by every request: reference data in, a Delivery out.
_DERIVATION = DeliveryDerivation(data.LOCATIONS, data.VOYAGES)


def get_calls(request: Request) -> SourceCalls:
    """The process-wide call log, created in the application's lifespan."""
    return request.app.state.calls


def get_store(request: Request) -> HandlingStore:
    """The process-wide handling store, created in the application's lifespan."""
    return request.app.state.store


def get_caches(request: Request) -> SourceCaches:
    """The process-wide source caches, created in the application's lifespan."""
    return request.app.state.caches


def get_context(
    calls: Annotated[SourceCalls, Depends(get_calls)],
    store: Annotated[HandlingStore, Depends(get_store)],
    caches: Annotated[SourceCaches, Depends(get_caches)],
) -> TrackingContext:
    request_id = str(uuid.uuid4())
    booking = BookingSource(calls, request_id)
    routing = RoutingSource(calls, request_id)
    voyage = VoyageSource(calls, request_id, caches.voyages)
    location = LocationSource(calls, request_id, caches.locations)
    handling = HandlingSource(calls, request_id, store, caches.handling)
    return TrackingContext(
        request_id,
        booking,
        routing,
        voyage,
        location,
        handling,
        _DERIVATION,
        Loaders.for_request(booking, routing, voyage, location, handling),
    )
