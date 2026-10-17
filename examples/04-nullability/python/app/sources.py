"""Ch4 Nullability and null propagation - the sources behind the resolvers.

Three small services stand in for the systems that own voyages, reference
locations and delivery state. Each has a different failure mode, and the
failure mode is what the chapter demonstrates:

* the voyage source *raises* for ``V404X`` (a service that is down);
* the location source *returns None* for a code it does not know (a dangling
  reference, ``XXBAD`` in the seed);
* the delivery source *raises* for cargo ``PQR234``.
"""
from __future__ import annotations

from datetime import datetime

import strawberry

from app.model import (
    CarrierMovement,
    Delivery,
    HandlingActivity,
    HandlingEventType,
    Location,
    RoutingStatus,
    TransportStatus,
    UnLocode,
    Voyage,
)


class SourceUnavailableError(Exception):
    """A source that cannot answer: the failure a resolver turns into an execution error."""


def utc(text: str) -> datetime:
    return datetime.fromisoformat(text)


def _location(un_locode: str, name: str, country: str) -> Location:
    return Location(
        id=strawberry.ID(f"loc_{un_locode}"),
        un_locode=UnLocode(un_locode),
        name=name,
        country=country,
    )


def _voyage(number: str, *schedule: CarrierMovement) -> Voyage:
    return Voyage(id=strawberry.ID(f"voy_{number}"), number=number, schedule=list(schedule))


NEW_YORK = _location("USNYC", "New York", "US")
ROTTERDAM = _location("NLRTM", "Rotterdam", "NL")
HAMBURG = _location("DEHAM", "Hamburg", "DE")
SINGAPORE = _location("SGSIN", "Singapore", "SG")
SHANGHAI = _location("CNSHA", "Shanghai", "CN")

V100S_DEPARTS = utc("2026-10-01T08:00:00+00:00")
V100S_ARRIVES = utc("2026-10-09T14:00:00+00:00")
V200E_DEPARTS = utc("2026-10-10T06:00:00+00:00")
V200E_ARRIVES = utc("2026-10-11T18:00:00+00:00")
FAULT_UNLOADS = utc("2026-10-28T14:00:00+00:00")

V100S = _voyage(
    "V100S",
    CarrierMovement(
        departure_location=NEW_YORK,
        arrival_location=HAMBURG,
        departure_time=V100S_DEPARTS,
        arrival_time=V100S_ARRIVES,
    ),
)
V200E = _voyage(
    "V200E",
    CarrierMovement(
        departure_location=HAMBURG,
        arrival_location=ROTTERDAM,
        departure_time=V200E_DEPARTS,
        arrival_time=V200E_ARRIVES,
    ),
)
V300A = _voyage(
    "V300A",
    CarrierMovement(
        departure_location=SINGAPORE,
        arrival_location=SHANGHAI,
        departure_time=utc("2026-11-02T04:00:00+00:00"),
        arrival_time=utc("2026-11-06T10:00:00+00:00"),
    ),
)

LOCATIONS = {loc.un_locode: loc for loc in (NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)}
VOYAGES = {voyage.number: voyage for voyage in (V100S, V200E, V300A)}

_FAULT_DELIVERY = Delivery(
    transport_status=TransportStatus.NOT_RECEIVED,
    routing_status=RoutingStatus.ROUTED,
    misdirected=False,
    last_known_location=None,
    current_voyage=None,
    estimated_time_of_arrival=FAULT_UNLOADS,
    next_expected_activity=HandlingActivity(
        type=HandlingEventType.RECEIVE, location=NEW_YORK, voyage=None
    ),
)
DELIVERIES = {
    "ABC123": Delivery(
        transport_status=TransportStatus.ONBOARD_CARRIER,
        routing_status=RoutingStatus.ROUTED,
        misdirected=False,
        last_known_location=NEW_YORK,
        current_voyage=V100S,
        estimated_time_of_arrival=V200E_ARRIVES,
        next_expected_activity=HandlingActivity(
            type=HandlingEventType.UNLOAD, location=HAMBURG, voyage=V100S
        ),
    ),
    "XYZ789": Delivery(
        transport_status=TransportStatus.NOT_RECEIVED,
        routing_status=RoutingStatus.NOT_ROUTED,
        misdirected=False,
        last_known_location=None,
        current_voyage=None,
        estimated_time_of_arrival=None,
        next_expected_activity=HandlingActivity(
            type=HandlingEventType.RECEIVE, location=SINGAPORE, voyage=None
        ),
    ),
    "JKL567": _FAULT_DELIVERY,
    "MNO901": _FAULT_DELIVERY,
}


class VoyageSource:
    """The voyage service behind ``Leg.voyage``. Raises for ``V404X``."""

    def get_voyage(self, voyage_number: str) -> Voyage | None:
        if voyage_number == "V404X":
            raise SourceUnavailableError("voyage service unavailable")
        return VOYAGES.get(voyage_number)


class LocationSource:
    """The location reference data. A code it does not know comes back as ``None``."""

    def get_location(self, un_locode: str) -> Location | None:
        return LOCATIONS.get(un_locode)


class DeliverySource:
    """The delivery service behind ``Cargo.delivery``. Raises for ``PQR234``."""

    def get_delivery(self, tracking_id: str) -> Delivery | None:
        if tracking_id == "PQR234":
            raise SourceUnavailableError("delivery service unavailable")
        return DELIVERIES.get(tracking_id)


voyage_source = VoyageSource()
location_source = LocationSource()
delivery_source = DeliverySource()
