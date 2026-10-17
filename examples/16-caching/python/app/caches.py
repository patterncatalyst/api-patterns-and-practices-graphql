"""Ch16 Caching - the field-level source caches.

Three ``cachetools.TTLCache`` instances sit under the loaders, at the bulk
sources: ``voyages`` and ``locations`` (reference data, 300 s) and ``handling``
(a cargo's events, ``TRACKING_HANDLING_CACHE_TTL_SECONDS``, evicted when an event is
registered). They are process-wide: they outlive a request, unlike a loader's own
cache (Chapter 13). A hit is not a call to an owner and is not logged.

``TTLCache`` is not thread-safe. Every access here runs on the event loop thread,
between awaits, so no lock is needed; a threaded server would need one.
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING

from cachetools import TTLCache

from app.settings import Settings

if TYPE_CHECKING:
    from app.handling import HandlingRecord
    from app.model import Location, Voyage

REFERENCE_TTL_SECONDS = 300
MAX_ENTRIES = 1024


@dataclass(frozen=True, slots=True)
class SourceCaches:
    voyages: TTLCache[str, Voyage]
    locations: TTLCache[str, Location]
    handling: TTLCache[str, list[HandlingRecord]]

    @classmethod
    def from_settings(cls, settings: Settings) -> SourceCaches:
        return cls(
            voyages=TTLCache(maxsize=MAX_ENTRIES, ttl=REFERENCE_TTL_SECONDS),
            locations=TTLCache(maxsize=MAX_ENTRIES, ttl=REFERENCE_TTL_SECONDS),
            handling=TTLCache(maxsize=MAX_ENTRIES, ttl=settings.handling_cache_ttl_seconds),
        )


def split[T](cache: TTLCache[str, T], keys: Sequence[str]) -> tuple[dict[str, T], list[str]]:
    """The cached values among ``keys``, and the distinct keys that missed.

    Only a found value is ever stored, so a key that is absent is a miss."""
    hits: dict[str, T] = {}
    misses: list[str] = []
    for key in dict.fromkeys(keys):
        value = cache.get(key)
        if value is None:
            misses.append(key)
        else:
            hits[key] = value
    return hits, misses
