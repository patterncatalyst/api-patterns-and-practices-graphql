"""Ch9 Error handling - the handling service's data.

``HandlingStore`` holds every recorded event, by cargo and by id, and the
idempotency index from a client's key to the event it produced. The store is
shared by every request. Its one compound step, "look the key up, and record
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


@dataclass(frozen=True, slots=True)
class HandlingRecord:
    id: str
    tracking_id: str
    type: HandlingEventType
    un_locode: str
    voyage_number: str | None
    completion_time: datetime
    registration_time: datetime


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
        # The seed: ABC123 was received in New York and loaded onto V100S.
        # A seeded event was registered five minutes after it completed.
        for handling in (
            NewHandling("ABC123", HandlingEventType.RECEIVE, "USNYC", None, _utc("2026-09-30T16:00:00+00:00")),
            NewHandling("ABC123", HandlingEventType.LOAD, "USNYC", "V100S", _utc("2026-10-01T08:30:00+00:00")),
        ):
            self._insert(handling, handling.completion_time + timedelta(minutes=5))

    def events(self, tracking_id: str) -> list[HandlingRecord]:
        """Every event recorded for the cargo; empty when there are none."""
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
            completion_time=handling.completion_time,
            registration_time=registered,
        )
        self._by_cargo.setdefault(event.tracking_id, []).append(event)
        self._by_id[event.id] = event
        return event
