"""Ch6 The execution model - the in-memory seed.

Five locations, three voyages and two cargos, the same data on both stacks. It
stands in for the services that own the data: the booking source reads
``CARGOS``, the routing source ``ITINERARIES``, the voyage and location
sources their own maps and the delivery source ``DELIVERIES``. Nothing reads
these except through ``app.sources``, which is what records the call.
"""
from __future__ import annotations

from datetime import UTC, datetime

import strawberry

from app.model import (
    Cargo,
    CarrierMovement,
    Delivery,
    HandlingActivity,
    HandlingEventType,
    Itinerary,
    Leg,
    Location,
    RouteSpecification,
    RoutingStatus,
    TrackingId,
    TransportStatus,
    UnLocode,
    Voyage,
)


def _utc(text: str) -> datetime:
    return datetime.fromisoformat(text).astimezone(UTC)


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

V100S_DEPARTS = _utc("2026-10-01T08:00:00+00:00")
V100S_ARRIVES = _utc("2026-10-09T14:00:00+00:00")
V200E_DEPARTS = _utc("2026-10-10T06:00:00+00:00")
V200E_ARRIVES = _utc("2026-10-11T18:00:00+00:00")

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
        departure_time=_utc("2026-11-02T04:00:00+00:00"),
        arrival_time=_utc("2026-11-06T10:00:00+00:00"),
    ),
)

ABC123 = Cargo(
    id=strawberry.ID("cargo_ABC123"),
    tracking_id=TrackingId("ABC123"),
    description="Palletized electronics",
    origin=NEW_YORK,
    destination=ROTTERDAM,
    route_specification=RouteSpecification(
        origin=NEW_YORK,
        destination=ROTTERDAM,
        arrival_deadline=_utc("2026-10-15T00:00:00+00:00"),
    ),
)

ABC123_ITINERARY = Itinerary(
    legs=[
        Leg(
            voyage_number="V100S",
            load_un_locode="USNYC",
            unload_un_locode="DEHAM",
            load_time=V100S_DEPARTS,
            unload_time=V100S_ARRIVES,
        ),
        Leg(
            voyage_number="V200E",
            load_un_locode="DEHAM",
            unload_un_locode="NLRTM",
            load_time=V200E_DEPARTS,
            unload_time=V200E_ARRIVES,
        ),
    ],
    final_arrival_date=V200E_ARRIVES,
)

ABC123_DELIVERY = Delivery(
    transport_status=TransportStatus.ONBOARD_CARRIER,
    routing_status=RoutingStatus.ROUTED,
    misdirected=False,
    last_known_location=NEW_YORK,
    current_voyage=V100S,
    estimated_time_of_arrival=V200E_ARRIVES,
    next_expected_activity=HandlingActivity(
        type=HandlingEventType.UNLOAD, location=HAMBURG, voyage=V100S
    ),
)

XYZ789 = Cargo(
    id=strawberry.ID("cargo_XYZ789"),
    tracking_id=TrackingId("XYZ789"),
    description="Frozen seafood",
    origin=SINGAPORE,
    destination=ROTTERDAM,
    route_specification=RouteSpecification(
        origin=SINGAPORE,
        destination=ROTTERDAM,
        arrival_deadline=_utc("2026-11-20T00:00:00+00:00"),
    ),
)

XYZ789_DELIVERY = Delivery(
    transport_status=TransportStatus.NOT_RECEIVED,
    routing_status=RoutingStatus.NOT_ROUTED,
    misdirected=False,
    last_known_location=None,
    current_voyage=None,
    estimated_time_of_arrival=None,
    next_expected_activity=HandlingActivity(
        type=HandlingEventType.RECEIVE, location=SINGAPORE, voyage=None
    ),
)

LOCATIONS = {loc.un_locode: loc for loc in (NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)}
VOYAGES = {voyage.number: voyage for voyage in (V100S, V200E, V300A)}
CARGOS = {cargo.tracking_id: cargo for cargo in (ABC123, XYZ789)}
ITINERARIES = {ABC123.tracking_id: ABC123_ITINERARY}
DELIVERIES = {ABC123.tracking_id: ABC123_DELIVERY, XYZ789.tracking_id: XYZ789_DELIVERY}
