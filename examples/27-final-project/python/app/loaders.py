"""Ch27 The final project - the per-request DataLoaders.

A ``DataLoader`` collects every ``load(key)`` made before the event loop's next
turn into one batch and calls its ``load_fn`` once with the distinct keys. The
``load_fn`` here calls a bulk read on the owning source and answers one value
per key, in the order of the keys; a key whose owner failed gets the exception
*instance* at its position, which fails that key's ``load`` and no other.

``Loaders`` is built once per request, in ``app/deps.py``, and carried on the
``TrackingContext``. The cache that makes a repeated key free lives inside each
loader, so it lives and dies with the request: nothing is shared between
requests, and a handling event registered by one request is visible to the next.
The loaders are keyed by value (a tracking id, a voyage number, a UN/LOCODE),
so every field that needs the same thing shares one loader: ``loadLocation`` and
``unloadLocation`` both use ``location``, ``itinerary`` and ``delivery`` both use
``itinerary``.
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from strawberry.dataloader import DataLoader

from app.handling import HandlingRecord
from app.model import Cargo, Itinerary, Location, Voyage
from app.sources import (
    BookingSource,
    HandlingSource,
    LocationSource,
    Outcome,
    RoutingSource,
    VoyageSource,
)


def _in_key_order[T](outcomes: Sequence[Outcome[T]]) -> list[T | None | Exception]:
    """The values for ``load_fn``: a failed key carries its exception instance."""
    return [o.error if o.error is not None else o.value for o in outcomes]


@dataclass(frozen=True, slots=True)
class Loaders:
    cargo: DataLoader[str, Cargo | None]
    itinerary: DataLoader[str, Itinerary | None]
    events: DataLoader[str, list[HandlingRecord]]
    voyage: DataLoader[str, Voyage | None]
    location: DataLoader[str, Location | None]

    @classmethod
    def for_request(
        cls,
        booking: BookingSource,
        routing: RoutingSource,
        voyage: VoyageSource,
        location: LocationSource,
        handling: HandlingSource,
    ) -> Loaders:
        """New loaders over this request's sources."""

        async def load_cargos(keys: list[str]) -> list[Cargo | None | Exception]:
            return _in_key_order(await booking.get_cargos(keys))

        async def load_itineraries(keys: list[str]) -> list[Itinerary | None | Exception]:
            return _in_key_order(await routing.get_itineraries(keys))

        async def load_events(keys: list[str]) -> list[list[HandlingRecord] | None | Exception]:
            return _in_key_order(await handling.list_events_for(keys))

        async def load_voyages(keys: list[str]) -> list[Voyage | None | Exception]:
            return _in_key_order(await voyage.get_voyages(keys))

        async def load_locations(keys: list[str]) -> list[Location | None | Exception]:
            return _in_key_order(await location.get_locations(keys))

        return cls(
            cargo=DataLoader(load_fn=load_cargos),
            itinerary=DataLoader(load_fn=load_itineraries),
            events=DataLoader(load_fn=load_events),
            voyage=DataLoader(load_fn=load_voyages),
            location=DataLoader(load_fn=load_locations),
        )
