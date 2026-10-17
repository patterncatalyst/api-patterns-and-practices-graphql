"""Ch18 AuthN and AuthZ - FastAPI dependencies.

``GraphQLRouter(schema, context_getter=get_context)`` calls ``get_context`` once
per request and passes the result to every resolver as ``info.context``. FastAPI
resolves ``get_context``'s own dependencies first, so the process-wide call log
arrives through ``Depends(get_calls)`` and the token validator through
``Depends(get_authenticator)``. The request's DataLoaders are built
here too, over the request's own sources: a loader and its cache never outlive
the request.
"""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Request

from app import data
from app.auth import Authenticator
from app.context import TrackingContext
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


def get_authenticator(request: Request) -> Authenticator:
    """The process-wide token validator, created in the application's lifespan."""
    return request.app.state.authenticator


async def get_context(
    request: Request,
    calls: Annotated[SourceCalls, Depends(get_calls)],
    store: Annotated[HandlingStore, Depends(get_store)],
    authenticator: Annotated[Authenticator, Depends(get_authenticator)],
) -> TrackingContext:
    # A bad bearer token is HTTP 401 here, before any GraphQL runs; no header is anonymous.
    identity = await authenticator.identity_from(request)
    request_id = str(uuid.uuid4())
    booking = BookingSource(calls, request_id, identity)
    routing = RoutingSource(calls, request_id)
    voyage = VoyageSource(calls, request_id)
    location = LocationSource(calls, request_id)
    handling = HandlingSource(calls, request_id, store)
    return TrackingContext(
        request_id,
        booking,
        routing,
        voyage,
        location,
        handling,
        _DERIVATION,
        Loaders.for_request(booking, routing, voyage, location, handling),
        identity,
    )
