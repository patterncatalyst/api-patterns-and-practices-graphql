"""Ch18 AuthN and AuthZ - the per-request GraphQL context type.

Every resolver receives the request's ``TrackingContext`` as ``info.context``.
It holds the request id (a uuid4, the same for every resolver of one request,
so every source call of one operation carries one id), the five sources bound
to that id, the request's ``Loaders`` and the caller's ``Identity`` (``None``
when anonymous). The identity is the only authentication state: the validated
token is not kept. ``app/deps.py`` builds it.

This module imports the source classes for type checking only. The resolvers in
``app/model.py`` annotate ``info`` with ``TrackingContext``, and the sources
import the model, so a runtime import here would be a cycle.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from strawberry.fastapi import BaseContext

if TYPE_CHECKING:
    from app.auth import Identity
    from app.derivation import DeliveryDerivation
    from app.loaders import Loaders
    from app.sources import (
        BookingSource,
        HandlingSource,
        LocationSource,
        RoutingSource,
        VoyageSource,
    )


class TrackingContext(BaseContext):
    def __init__(
        self,
        request_id: str,
        booking: BookingSource,
        routing: RoutingSource,
        voyage: VoyageSource,
        location: LocationSource,
        handling: HandlingSource,
        derivation: DeliveryDerivation,
        loaders: Loaders,
        identity: Identity | None,
    ) -> None:
        super().__init__()
        self.request_id = request_id
        self.booking = booking
        self.routing = routing
        self.voyage = voyage
        self.location = location
        self.handling = handling
        self.derivation = derivation
        self.loaders = loaders
        self.identity = identity
