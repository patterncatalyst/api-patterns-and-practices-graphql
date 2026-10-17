"""Ch23 Testing GraphQL APIs - what the two connections share.

The argument rules, the cursor codec and the slice algorithm of the Relay Cursor
Connections specification.

A cursor is opaque to a client but not to the server: base64url, without
padding, of ``<prefix>|v1|<sort key fields>``. The prefix names the connection,
so a cursor from one connection is rejected by another, and the version lets the
format change without misreading old cursors. Paging seeks on the sort
key and never counts rows from the start, which is why an insert cannot shift a
page.

This module imports nothing from the rest of the app except ``app.errors``, so
the model, the sources and the seed can all use it.
"""
from __future__ import annotations

import base64
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import NamedTuple

from strawberry import Some

from app.errors import BadUserInput

DEFAULT_PAGE_SIZE = 10
MAX_PAGE_SIZE = 50
_VERSION = "v1"
_TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class CargoKey(NamedTuple):
    """The position of a cargo in ``cargos``: newest booking first."""

    booked_at: datetime
    tracking_id: str


class EventKey(NamedTuple):
    """The position of an event in ``handlingHistory``: newest completion first."""

    completion_time: datetime
    sequence: int


@dataclass(frozen=True, slots=True)
class Page[K]:
    """Validated page arguments. Exactly one of ``first`` and ``last`` is set;
    ``after`` and ``before`` are decoded cursors, or ``None``."""

    first: int | None
    last: int | None
    after: K | None
    before: K | None


@dataclass(frozen=True, slots=True)
class Slice[T]:
    """One page of a connection, in connection order, with both directions answered exactly."""

    items: list[T]
    has_next: bool
    has_previous: bool
    total_count: int


def argument[T](maybe: Some[T | None] | None) -> T | None:
    """The value of a ``strawberry.Maybe`` argument: ``None`` when absent or null."""
    return maybe.value if maybe is not None else None


def parse_page[K](
    first: int | None,
    after: str | None,
    last: int | None,
    before: str | None,
    decode_cursor: Callable[[str], K],
) -> Page[K]:
    """Validate the arguments, in this order: the range of each size, then the
    combination, then each cursor. With neither size the page is the first 10."""
    _check_size("first", first)
    _check_size("last", last)
    if first is not None and last is not None:
        raise BadUserInput("first and last cannot be combined")
    after_key = _decode("after", after, decode_cursor)
    before_key = _decode("before", before, decode_cursor)
    if first is None and last is None:
        first = DEFAULT_PAGE_SIZE
    return Page(first, last, after_key, before_key)


def slice_[T, K](newest_first: Sequence[T], key: Callable[[T], K], page: Page[K]) -> Slice[T]:
    """The slice algorithm of "Pagination algorithm" in the specification: take
    the edges after the ``after`` cursor and before the ``before`` cursor, then
    the first or last N of those. ``newest_first`` is in connection order, so a
    larger key comes earlier."""
    total = len(newest_first)
    # Items at or before the cursor in connection order are those with a key >= the cursor's.
    start = 0 if page.after is None else sum(1 for item in newest_first if key(item) >= page.after)
    end = total if page.before is None else sum(1 for item in newest_first if key(item) > page.before)
    end = max(start, end)
    if page.first is not None:
        end = min(end, start + page.first)
    if page.last is not None:
        start = max(start, end - page.last)
    return Slice(list(newest_first[start:end]), end < total, start > 0, total)


def encode_cargo(key: CargoKey) -> str:
    return _encode("cargo", _format_time(key.booked_at), key.tracking_id)


def decode_cargo(cursor: str) -> CargoKey:
    time_text, tracking_id = _decode_fields(cursor, "cargo")
    if not tracking_id:
        raise ValueError("empty key")
    return CargoKey(_parse_time(time_text), tracking_id)


def encode_event(key: EventKey) -> str:
    return _encode("evt", _format_time(key.completion_time), str(key.sequence))


def decode_event(cursor: str) -> EventKey:
    time_text, sequence_text = _decode_fields(cursor, "evt")
    sequence = int(sequence_text)
    if sequence < 1 or str(sequence) != sequence_text:
        raise ValueError("not a sequence number")
    return EventKey(_parse_time(time_text), sequence)


def _encode(prefix: str, *fields: str) -> str:
    text = "|".join((prefix, _VERSION, *fields))
    return base64.urlsafe_b64encode(text.encode()).rstrip(b"=").decode()


def _decode_fields(cursor: str, prefix: str) -> tuple[str, str]:
    """The fields after the prefix and version; raises for any cursor this codec did not issue."""
    raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4))
    # Only the canonical encoding is accepted: no padding, no stray characters.
    if base64.urlsafe_b64encode(raw).rstrip(b"=").decode() != cursor:
        raise ValueError("not canonical base64url")
    parts = raw.decode().split("|")
    if len(parts) != 4 or parts[0] != prefix or parts[1] != _VERSION:
        raise ValueError("wrong prefix, version or field count")
    return parts[2], parts[3]


def _format_time(value: datetime) -> str:
    return value.astimezone(UTC).strftime(_TIME_FORMAT)


def _parse_time(text: str) -> datetime:
    """A time in the cursor must be the exact text this codec writes."""
    parsed = datetime.strptime(text, _TIME_FORMAT).replace(tzinfo=UTC)
    if _format_time(parsed) != text:
        raise ValueError("not a whole-second UTC time")
    return parsed


def _check_size(name: str, size: int | None) -> None:
    if size is not None and not 0 <= size <= MAX_PAGE_SIZE:
        raise BadUserInput(f"{name} must be between 0 and {MAX_PAGE_SIZE}")


def _decode[K](name: str, cursor: str | None, decode_cursor: Callable[[str], K]) -> K | None:
    if cursor is None:
        return None
    try:
        return decode_cursor(cursor)
    except Exception as error:
        raise BadUserInput(f"{name} is not a valid cursor for this connection") from error
