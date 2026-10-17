"""Ch21 Real-time - the per-request GraphQL context type.

Every resolver receives the request's ``TrackingContext`` as ``info.context``.
It holds the request id (a uuid4, the same for every resolver of one request,
so every source call of one operation carries one id), the five sources bound
to that id, and the request's ``Loaders``. ``app/deps.py`` builds it.

A subscription keeps one context, and one request id, for as long as it runs.
``begin_event`` gives each of its events what a request gets: new loaders, so a
loader's cache never carries one event's reads into the next.

This module imports the source classes for type checking only. The resolvers in
``app/model.py`` annotate ``info`` with ``TrackingContext``, and the sources
import the model, so a runtime import here would be a cycle.
"""
from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from strawberry.fastapi import BaseContext

if TYPE_CHECKING:
    from app.derivation import DeliveryDerivation
    from app.handling import HandlingStore
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
        store: HandlingStore,
        new_loaders: Callable[[], Loaders],
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
        self.store = store
        self._new_loaders = new_loaders

    def begin_event(self) -> None:
        """Give the next event of a subscription loaders with empty caches."""
        self.loaders = self._new_loaders()
