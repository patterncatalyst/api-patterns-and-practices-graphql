"""Ch8 Mutations and input types - FastAPI dependencies.

``GraphQLRouter(schema, context_getter=get_context)`` calls ``get_context`` once
per request and passes the result to every resolver as ``info.context``. FastAPI
resolves ``get_context``'s own dependencies first, so the process-wide call log
arrives through ``Depends(get_calls)``.
"""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Request

from app import data
from app.context import TrackingContext
from app.derivation import DeliveryDerivation
from app.handling import HandlingStore
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


def get_context(
    calls: Annotated[SourceCalls, Depends(get_calls)],
    store: Annotated[HandlingStore, Depends(get_store)],
) -> TrackingContext:
    request_id = str(uuid.uuid4())
    return TrackingContext(
        request_id,
        BookingSource(calls, request_id),
        RoutingSource(calls, request_id),
        VoyageSource(calls, request_id),
        LocationSource(calls, request_id),
        HandlingSource(calls, request_id, store),
        _DERIVATION,
    )
