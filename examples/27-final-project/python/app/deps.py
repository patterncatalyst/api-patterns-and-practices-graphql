"""Ch27 The final project - FastAPI dependencies.

``GraphQLRouter(schema, context_getter=get_context)`` calls ``get_context`` once
per request (per connection on the WebSocket transports) and passes the result
to every resolver as ``info.context``. A subscription's loaders are renewed for
each event with ``TrackingContext.begin_event``. FastAPI resolves
``get_context``'s own dependencies first, so the process-wide call log
arrives through ``Depends(get_calls)`` and the token validator through
``Depends(get_authenticator)``. The request's DataLoaders are built
here too, over the request's own sources: a loader and its cache never outlive
the request, or the event of a subscription.
"""
from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends
from starlette.requests import HTTPConnection

from app import data
from app.auth import Authenticator, Identity
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


def get_calls(connection: HTTPConnection) -> SourceCalls:
    """The process-wide call log, created in the application's lifespan.
    ``HTTPConnection`` is the base of both ``Request`` and ``WebSocket``, so the
    same dependency serves HTTP and the WebSocket transport."""
    return connection.app.state.calls


def get_store(connection: HTTPConnection) -> HandlingStore:
    """The process-wide handling store, created in the application's lifespan."""
    return connection.app.state.store


def get_authenticator(connection: HTTPConnection) -> Authenticator:
    """The process-wide token validator, created in the application's lifespan."""
    return connection.app.state.authenticator


async def get_identity(
    connection: HTTPConnection, authenticator: Annotated[Authenticator, Depends(get_authenticator)]
) -> Identity | None:
    """The caller's identity from the bearer token, ``None`` when anonymous."""
    return await authenticator.identity_from(connection)


async def get_context(
    identity: Annotated[Identity | None, Depends(get_identity)],
    calls: Annotated[SourceCalls, Depends(get_calls)],
    store: Annotated[HandlingStore, Depends(get_store)],
) -> TrackingContext:
    # A bad bearer token is HTTP 401 here, before any GraphQL runs (a refused upgrade on
    # a WebSocket); no header is anonymous.
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
        store,
        lambda: Loaders.for_request(booking, routing, voyage, location, handling),
        identity,
    )
