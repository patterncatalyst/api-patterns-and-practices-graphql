"""Ch15 Persisted queries and APQ - the five sources and the source-call log.

Each source stands in for the service that owns the data. Besides the
single-key reads, the owners offer bulk reads (``get_cargos``, ``get_itineraries``,
``get_voyages``, ``get_locations``, ``list_events_for``): one call for many keys,
logged once under the sorted distinct keys joined with ``+``. A lookup is a
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
from collections.abc import Awaitable, Callable, Sequence
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


@dataclass(frozen=True, slots=True)
class Outcome[T]:
    """What a bulk read returns for one key: the value (``None`` when the owner
    has nothing under that key) or the failure it reported for that key alone."""

    value: T | None = None
    error: SourceUnavailable | None = None


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

    async def call_batch[T](
        self,
        request: str,
        source: str,
        op: str,
        keys: Sequence[str],
        lookup: Callable[[str], T],
    ) -> list[Outcome[T]]:
        """One call for many keys. It is logged once, under the sorted distinct
        keys joined with ``+``, and answers one ``Outcome`` per requested key in
        the order asked. A key whose lookup raises ``SourceUnavailable`` fails
        alone: its outcome carries the error, the others carry their values."""
        distinct = sorted(set(keys))

        def lookup_all() -> list[Outcome[T]]:
            by_key: dict[str, Outcome[T]] = {}
            for key in distinct:
                try:
                    by_key[key] = Outcome(lookup(key))
                except SourceUnavailable as error:
                    by_key[key] = Outcome(error=error)
            return [by_key[key] for key in keys]

        return await self.call(request, source, op, "+".join(distinct), lookup_all)

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
    """The booking service: ``getCargo``, ``getCargos`` and ``listCargos``. It lists ``GHI345``
    but cannot load it: the index is a separate, healthy store, which is what
    lets one edge fail while its page does not."""

    calls: SourceCalls
    request: str

    async def get_cargo(self, tracking_id: str) -> Cargo | None:
        """Raises ``SourceUnavailable`` for ``GHI345``."""

        return await self.calls.call(
            self.request, "booking", "getCargo", tracking_id, lambda: self._load(tracking_id)
        )

    async def get_cargos(self, tracking_ids: Sequence[str]) -> list[Outcome[Cargo]]:
        """Many cargos in one call. One outcome per tracking id, in the order
        asked: the cargo, ``None`` when unknown, or the failure for that id
        alone (``GHI345``)."""
        return await self.calls.call_batch(
            self.request, "booking", "getCargos", tracking_ids, self._load
        )

    @staticmethod
    def _load(tracking_id: str) -> Cargo | None:
        if tracking_id == "GHI345":
            raise SourceUnavailable("booking service unavailable")
        return data.CARGOS.get(tracking_id)

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

    async def get_itineraries(self, tracking_ids: Sequence[str]) -> list[Outcome[Itinerary]]:
        """Many itineraries in one call: one outcome per tracking id, in the
        order asked; ``None`` when unrouted."""
        return await self.calls.call_batch(
            self.request, "routing", "getItineraries", tracking_ids, data.ITINERARIES.get
        )

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

    async def get_voyages(self, numbers: Sequence[str]) -> list[Outcome[Voyage]]:
        """Many voyages in one call: one outcome per voyage number, in the
        order asked; ``None`` when unknown."""
        return await self.calls.call_batch(
            self.request, "voyage", "getVoyages", numbers, data.VOYAGES.get
        )

    async def get_voyage(self, number: str) -> Voyage | None:
        return await self.calls.call(
            self.request, "voyage", "getVoyage", number, lambda: data.VOYAGES.get(number)
        )


@dataclass(frozen=True, slots=True)
class LocationSource:
    calls: SourceCalls
    request: str

    async def get_locations(self, un_locodes: Sequence[str]) -> list[Outcome[Location]]:
        """Many locations in one call: one outcome per UN/LOCODE, in the order
        asked; ``None`` when unknown."""
        return await self.calls.call_batch(
            self.request, "location", "getLocations", un_locodes, data.LOCATIONS.get
        )

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
    """The handling service: the reads ``listEvents``, ``listEventsFor``, ``pageEvents``, ``getEvent``
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

    async def list_events_for(
        self, tracking_ids: Sequence[str]
    ) -> list[Outcome[list[HandlingRecord]]]:
        """The events of many cargos in one call: one outcome per tracking id, in
        the order asked, each an empty list when the cargo has none."""
        return await self.calls.call_batch(
            self.request, "handling", "listEventsFor", tracking_ids, self.store.events
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
