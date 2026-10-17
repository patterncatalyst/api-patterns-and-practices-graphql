"""Ch25 Local with Docker Compose - the handling service's data.

``HandlingStore`` holds every recorded event, by cargo and by id, and the
idempotency index from a client's key to the event it produced. The store is
shared by every request. Each cargo's events are kept newest first by completion
time and then by id sequence, so ``handlingHistory`` reads them already in
connection order and an event registered late lands in its place. Its one compound step, "look the key up, and record
the event only if it is absent", runs under an ``asyncio.Lock``, so two requests
carrying the same key cannot both record an event.

A stored ``HandlingRecord`` is the internal form; the GraphQL ``HandlingEvent``
type in ``app/model.py`` is built from it.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from app.model import HandlingEventType
from app.pagination import EventKey


@dataclass(frozen=True, slots=True)
class HandlingRecord:
    id: str
    tracking_id: str
    type: HandlingEventType
    un_locode: str
    voyage_number: str | None
    completion_time: datetime
    registration_time: datetime

    @property
    def sequence(self) -> int:
        """The number in ``evt_<n>``: ids are issued in registration order."""
        return int(self.id.removeprefix("evt_"))

    @property
    def key(self) -> EventKey:
        """The position of this event in ``handlingHistory``."""
        return EventKey(self.completion_time, self.sequence)


@dataclass(frozen=True, slots=True)
class NewHandling:
    """A validated registration, before the store gives it an id and a registration time."""

    tracking_id: str
    type: HandlingEventType
    un_locode: str
    voyage_number: str | None
    completion_time: datetime


@dataclass(frozen=True, slots=True)
class Appended:
    """What ``append`` did: the event now on record, and whether this call wrote it."""

    event: HandlingRecord
    created: bool


def _now() -> datetime:
    """The server clock in whole seconds, the wire format of ``DateTime``."""
    return datetime.now(UTC).replace(microsecond=0)


def _utc(text: str) -> datetime:
    return datetime.fromisoformat(text).astimezone(UTC)


class HandlingStore:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._last_number = 0
        self._by_cargo: dict[str, list[HandlingRecord]] = {}
        self._by_id: dict[str, HandlingRecord] = {}
        self._by_idempotency_key: dict[str, HandlingRecord] = {}
        # The seed: ABC123 was received in New York and loaded onto V100S (evt_1, evt_2);
        # DEF456 made the whole trip and was claimed in Rotterdam (evt_3 to evt_9).
        # A seeded event was registered five minutes after it completed.
        for tracking_id, type_, un_locode, voyage_number, completed in (
            ("ABC123", HandlingEventType.RECEIVE, "USNYC", None, "2026-09-30T16:00:00+00:00"),
            ("ABC123", HandlingEventType.LOAD, "USNYC", "V100S", "2026-10-01T08:30:00+00:00"),
            ("DEF456", HandlingEventType.RECEIVE, "USNYC", None, "2026-09-30T15:00:00+00:00"),
            ("DEF456", HandlingEventType.LOAD, "USNYC", "V100S", "2026-10-01T08:15:00+00:00"),
            ("DEF456", HandlingEventType.UNLOAD, "DEHAM", "V100S", "2026-10-09T14:30:00+00:00"),
            ("DEF456", HandlingEventType.LOAD, "DEHAM", "V200E", "2026-10-10T06:15:00+00:00"),
            ("DEF456", HandlingEventType.UNLOAD, "NLRTM", "V200E", "2026-10-11T18:20:00+00:00"),
            ("DEF456", HandlingEventType.CUSTOMS, "NLRTM", None, "2026-10-12T08:00:00+00:00"),
            ("DEF456", HandlingEventType.CLAIM, "NLRTM", None, "2026-10-12T15:00:00+00:00"),
        ):
            completion_time = _utc(completed)
            self._insert(
                NewHandling(tracking_id, type_, un_locode, voyage_number, completion_time),
                completion_time + timedelta(minutes=5),
            )

    def events(self, tracking_id: str) -> list[HandlingRecord]:
        """Every event recorded for the cargo, newest first; empty when there are none."""
        return list(self._by_cargo.get(tracking_id, []))

    def event(self, event_id: str) -> HandlingRecord | None:
        return self._by_id.get(event_id)

    def find_by_idempotency_key(self, key: str) -> HandlingRecord | None:
        return self._by_idempotency_key.get(key)

    async def append(self, handling: NewHandling, idempotency_key: str | None) -> Appended:
        """Record the event. With a key, a second call with the same key returns
        the first event and writes nothing; without one, every call writes."""
        async with self._lock:
            if idempotency_key is not None and (
                existing := self._by_idempotency_key.get(idempotency_key)
            ):
                return Appended(existing, created=False)
            event = self._insert(handling, _now())
            if idempotency_key is not None:
                self._by_idempotency_key[idempotency_key] = event
            return Appended(event, created=True)

    def _insert(self, handling: NewHandling, registered: datetime) -> HandlingRecord:
        self._last_number += 1
        event = HandlingRecord(
            id=f"evt_{self._last_number}",
            tracking_id=handling.tracking_id,
            type=handling.type,
            un_locode=handling.un_locode,
            voyage_number=handling.voyage_number,
            completion_time=handling.completion_time.replace(microsecond=0),
            registration_time=registered,
        )
        events = self._by_cargo.setdefault(event.tracking_id, [])
        events.append(event)
        events.sort(key=lambda e: e.key, reverse=True)
        self._by_id[event.id] = event
        return event
