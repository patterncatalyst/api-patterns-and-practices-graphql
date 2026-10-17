"""Resolver layer with a stubbed source.

``schema.execute`` runs the resolvers with a context the test builds,
so the booking service can fail on demand and no HTTP layer is involved.
"""
import pytest

from app.deps import get_context
from app.errors import SourceUnavailable
from app.handling import HandlingStore
from app.schema import schema
from app.sources import BookingSource, SourceCalls

pytestmark = pytest.mark.anyio


class UnavailableBooking(BookingSource):
    """A booking service that cannot answer."""

    async def get_cargo(self, tracking_id: str):
        raise SourceUnavailable("booking service unavailable")


def context_with(booking_class: type[BookingSource]):
    context = get_context(SourceCalls(0), HandlingStore())
    context.booking = booking_class(context.booking.calls, context.request_id)
    return context


async def test_an_unavailable_booking_service_is_an_error_at_the_cargo_field_with_its_code() -> None:
    result = await schema.execute(
        '{ cargo(trackingId: "ABC123") { trackingId } }',
        context_value=context_with(UnavailableBooking),
    )

    assert result.data == {"cargo": None}
    assert len(result.errors) == 1
    error = result.errors[0]
    assert error.path == ["cargo"]
    assert error.message == "booking service unavailable"
    assert error.extensions == {"code": "SERVICE_UNAVAILABLE"}


async def test_the_same_resolver_answers_when_the_booking_service_is_healthy() -> None:
    result = await schema.execute(
        '{ cargo(trackingId: "ABC123") { trackingId } }',
        context_value=context_with(BookingSource),
    )

    assert result.errors is None
    assert result.data == {"cargo": {"trackingId": "ABC123"}}
