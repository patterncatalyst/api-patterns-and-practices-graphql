"""Ch12 Connections and pagination - the five sources and the source-call log.

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
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from app import data
from app.errors import SourceUnavailable
from app.handling import Appended, HandlingRecord, HandlingStore, NewHandling
from app.model import Cargo, Itinerary, Location, RoutingStatus, Voyage
from app.pagination import CargoKey, EventKey, Page, Slice, slice_

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

    async def write[T](
        self,
        request: str,
        source: str,
        op: str,
        write: Callable[[], Awaitable[T]],
        log_key: Callable[[T], str | None],
    ) -> T:
        """Like ``call``, for an operation that writes. The write runs once the
        latency has passed, and ``log_key`` names the entry from its result; a
        ``None`` key logs nothing, so an operation that turned out not to write
        leaves no trace in a log whose entries mean "wrote"."""
        start_ms = _now_ms()
        await asyncio.sleep(self._latency)
        result = await write()
        key = log_key(result)
        if key is not None:
            self._calls.append(SourceCall(request, source, op, key, start_ms, _now_ms()))
        return result

    def snapshot(self) -> list[SourceCall]:
        """The log so far, ordered by start time."""
        return sorted(self._calls, key=lambda c: c.start_ms)

    def reset(self) -> None:
        self._calls.clear()


@dataclass(frozen=True, slots=True)
class BookingSource:
    """The booking service: ``getCargo`` and ``listCargos``. It lists ``GHI345``
    but cannot load it: the index is a separate, healthy store, which is what
    lets one edge fail while its page does not."""

    calls: SourceCalls
    request: str

    async def get_cargo(self, tracking_id: str) -> Cargo | None:
        """Raises ``SourceUnavailable`` for ``GHI345``."""

        def lookup() -> Cargo | None:
            if tracking_id == "GHI345":
                raise SourceUnavailable("booking service unavailable")
            return data.CARGOS.get(tracking_id)

        return await self.calls.call(self.request, "booking", "getCargo", tracking_id, lookup)

    async def list_cargos(
        self, routing_status: RoutingStatus | None, page: Page[CargoKey]
    ) -> Slice[data.BookingEntry]:
        """One page of the booking index, newest booking first, optionally only
        the rows with ``routing_status``. The log key is the filter, or ``*``."""
        key = routing_status.value if routing_status else "*"
        return await self.calls.call(
            self.request,
            "booking",
            "listCargos",
            key,
            lambda: slice_(
                [
                    row
                    for row in data.BOOKING_INDEX
                    if routing_status is None or row.routing_status is routing_status
                ],
                lambda row: row.key,
                page,
            ),
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
    """The handling service: the reads ``listEvents``, ``pageEvents``, ``getEvent``
    and ``findByIdempotencyKey``, and the write ``appendEvent``."""

    calls: SourceCalls
    request: str
    store: HandlingStore

    async def list_events(self, tracking_id: str) -> list[HandlingRecord]:
        """Every handling event recorded for the cargo; empty when there are none."""
        return await self.calls.call(
            self.request,
            "handling",
            "listEvents",
            tracking_id,
            lambda: self.store.events(tracking_id),
        )

    async def page_events(self, tracking_id: str, page: Page[EventKey]) -> Slice[HandlingRecord]:
        """One page of the cargo's events, newest completion first. The log key is the tracking id."""
        return await self.calls.call(
            self.request,
            "handling",
            "pageEvents",
            tracking_id,
            lambda: slice_(self.store.events(tracking_id), lambda event: event.key, page),
        )

    async def get_event(self, event_id: str) -> HandlingRecord | None:
        return await self.calls.call(
            self.request, "handling", "getEvent", event_id, lambda: self.store.event(event_id)
        )

    async def find_by_idempotency_key(self, key: str) -> HandlingRecord | None:
        """The event a key already produced, or ``None`` when the key is new."""
        return await self.calls.call(
            self.request,
            "handling",
            "findByIdempotencyKey",
            key,
            lambda: self.store.find_by_idempotency_key(key),
        )

    async def append_event(self, handling: NewHandling, idempotency_key: str | None) -> Appended:
        """Record the event, or return the event the key already produced. The log
        entry is keyed by the new event's id and exists only when this call
        wrote: a call that lost a race to the same key writes, and logs, nothing."""
        return await self.calls.write(
            self.request,
            "handling",
            "appendEvent",
            lambda: self.store.append(handling, idempotency_key),
            lambda appended: appended.event.id if appended.created else None,
        )
