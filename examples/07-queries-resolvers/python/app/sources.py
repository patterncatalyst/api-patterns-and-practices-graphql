"""Ch7 Queries and resolvers - the five sources and the source-call log.

Each source stands in for the service that owns the data. A lookup is a
coroutine: it awaits the configured latency without holding a thread, so while
one call waits the event loop runs the others. ``SourceCalls.call`` records
every call (request, source, operation, key, start and end on a monotonic
clock); verify.sh reads that log to check execution order and overlap. The log
is not part of the GraphQL schema.

A source object is bound to one request id, so every call it makes is tagged
with the request that made it. ``TrackingContext`` builds the five per request.
"""
from __future__ import annotations

import asyncio
import time
from collections.abc import Callable
from dataclasses import dataclass

from app import data
from app.handling import HandlingRecord
from app.model import Cargo, Itinerary, Location, Voyage

_ORIGIN = time.perf_counter()


def _now_ms() -> int:
    return int((time.perf_counter() - _ORIGIN) * 1000)


@dataclass(frozen=True, slots=True)
class SourceCall:
    """One entry of the log: who called which source operation with which key, and when."""

    request: str
    source: str
    op: str
    key: str
    start_ms: int
    end_ms: int


class SourceCalls:
    """The seam every source goes through: latency plus the call log."""

    def __init__(self, latency_ms: int) -> None:
        self._latency = latency_ms / 1000
        self._calls: list[SourceCall] = []

    async def call[T](
        self, request: str, source: str, op: str, key: str, lookup: Callable[[], T]
    ) -> T:
        """Run ``lookup`` after the latency; log the call when it ends, however it ends."""
        start_ms = _now_ms()
        try:
            await asyncio.sleep(self._latency)
            return lookup()
        finally:
            self._calls.append(SourceCall(request, source, op, key, start_ms, _now_ms()))

    def snapshot(self) -> list[SourceCall]:
        """The log so far, ordered by start time."""
        return sorted(self._calls, key=lambda c: c.start_ms)

    def reset(self) -> None:
        self._calls.clear()


@dataclass(frozen=True, slots=True)
class BookingSource:
    calls: SourceCalls
    request: str

    async def get_cargo(self, tracking_id: str) -> Cargo | None:
        return await self.calls.call(
            self.request, "booking", "getCargo", tracking_id, lambda: data.CARGOS.get(tracking_id)
        )


@dataclass(frozen=True, slots=True)
class RoutingSource:
    calls: SourceCalls
    request: str

    async def get_itinerary(self, tracking_id: str) -> Itinerary | None:
        return await self.calls.call(
            self.request,
            "routing",
            "getItinerary",
            tracking_id,
            lambda: data.ITINERARIES.get(tracking_id),
        )


@dataclass(frozen=True, slots=True)
class VoyageSource:
    calls: SourceCalls
    request: str

    async def get_voyage(self, number: str) -> Voyage | None:
        return await self.calls.call(
            self.request, "voyage", "getVoyage", number, lambda: data.VOYAGES.get(number)
        )


@dataclass(frozen=True, slots=True)
class LocationSource:
    calls: SourceCalls
    request: str

    async def get_location(self, un_locode: str) -> Location | None:
        return await self.calls.call(
            self.request,
            "location",
            "getLocation",
            un_locode,
            lambda: data.LOCATIONS.get(un_locode),
        )


@dataclass(frozen=True, slots=True)
class HandlingSource:
    calls: SourceCalls
    request: str

    async def list_events(self, tracking_id: str) -> list[HandlingRecord]:
        """Every handling event recorded for the cargo; empty when there are none."""
        return await self.calls.call(
            self.request,
            "handling",
            "listEvents",
            tracking_id,
            lambda: list(data.EVENTS.get(tracking_id, [])),
        )
