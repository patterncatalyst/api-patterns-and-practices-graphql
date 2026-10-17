"""Ch27 The final project - registering a handling event.

``register`` validates the domain rules, then records the event once. The steps
run in this order and stop at the first that decides the outcome:

1. look up the cargo, the location and (when a voyage is named) the voyage, all
   at once;
2. collect *every* domain failure, in the order trackingId, location,
   voyageNumber, completionTime; any failure returns a payload of ``userErrors``
   and writes nothing;
3. with an idempotency key, return the event the key already produced;
4. otherwise append the event, atomically with respect to the key.

Input coercion has already happened by the time this runs: a malformed input
is rejected before it.
"""
from __future__ import annotations

import asyncio
from datetime import UTC, datetime

from strawberry import Some

from app.context import TrackingContext
from app.handling import HandlingRecord, NewHandling
from app.model import (
    Cargo,
    HandlingEvent,
    HandlingEventType,
    Location,
    RegisterHandlingEventInput,
    RegisterHandlingEventPayload,
    UserError,
    UserErrorCode,
    Voyage,
)

_VOYAGE_TYPES = (HandlingEventType.LOAD, HandlingEventType.UNLOAD)


def _value[T](maybe: Some[T | None] | None) -> T | None:
    """The value of a ``strawberry.Maybe`` input field: ``None`` when absent or null."""
    return maybe.value if maybe is not None else None


async def _none() -> None:
    return None


async def register(
    ctx: TrackingContext, data: RegisterHandlingEventInput
) -> RegisterHandlingEventPayload:
    voyage_number: str | None = _value(data.voyage_number)
    key: str | None = _value(data.idempotency_key)
    needs_voyage = data.type in _VOYAGE_TYPES

    cargo, location, voyage = await asyncio.gather(
        ctx.booking.get_cargo(data.tracking_id),
        ctx.location.get_location(data.location),
        ctx.voyage.get_voyage(voyage_number) if needs_voyage and voyage_number else _none(),
    )
    errors = _validate(data, voyage_number, cargo, location, voyage)
    if errors:
        return RegisterHandlingEventPayload(handling_event=None, cargo=None, user_errors=errors)

    original: HandlingRecord | None = (
        await ctx.handling.find_by_idempotency_key(key) if key is not None else None
    )
    if original is None:
        original = (
            await ctx.handling.append_event(
                NewHandling(
                    data.tracking_id,
                    data.type,
                    data.location,
                    voyage_number,
                    data.completion_time,
                ),
                key,
            )
        ).event
    recorded_cargo = cargo if original.tracking_id == data.tracking_id else None
    if recorded_cargo is None:
        recorded_cargo = await ctx.booking.get_cargo(original.tracking_id)
    return RegisterHandlingEventPayload(
        handling_event=HandlingEvent.of(original), cargo=recorded_cargo, user_errors=[]
    )


def _validate(
    data: RegisterHandlingEventInput,
    voyage_number: str | None,
    cargo: Cargo | None,
    location: Location | None,
    voyage: Voyage | None,
) -> list[UserError]:
    errors: list[UserError] = []
    if cargo is None:
        errors.append(
            UserError(
                code=UserErrorCode.UNKNOWN_CARGO,
                message=f"No cargo has tracking id {data.tracking_id}.",
                field=["input", "trackingId"],
            )
        )
    if location is None:
        errors.append(
            UserError(
                code=UserErrorCode.UNKNOWN_LOCATION,
                message=f"No location has UN/LOCODE {data.location}.",
                field=["input", "location"],
            )
        )
    needs_voyage = data.type in _VOYAGE_TYPES
    if needs_voyage and voyage_number is None:
        errors.append(
            UserError(
                code=UserErrorCode.VOYAGE_REQUIRED,
                message=f"{data.type.value} events must name a voyage.",
                field=["input", "voyageNumber"],
            )
        )
    elif not needs_voyage and voyage_number is not None:
        errors.append(
            UserError(
                code=UserErrorCode.VOYAGE_NOT_ALLOWED,
                message=f"{data.type.value} events must not name a voyage.",
                field=["input", "voyageNumber"],
            )
        )
    elif needs_voyage and voyage is None:
        errors.append(
            UserError(
                code=UserErrorCode.UNKNOWN_VOYAGE,
                message=f"No voyage has number {voyage_number}.",
                field=["input", "voyageNumber"],
            )
        )
    if data.completion_time > datetime.now(UTC):
        errors.append(
            UserError(
                code=UserErrorCode.INVALID_COMPLETION_TIME,
                message=f"The completion time {data.completion_time:%Y-%m-%dT%H:%M:%SZ} is in the future.",
                field=["input", "completionTime"],
            )
        )
    return errors
