"""Ch9 Error handling - the in-memory seed.

Five locations, three voyages and five cargos, the same data on both stacks.
Three cargos are fault seeds, each breaking one source: ``JKL567`` sails on
``V404X``, a voyage the voyage service cannot serve; ``MNO901`` loads at
``XXBAD``, a code the location service does not know; ``PQR234`` is healthy
except that the handling service fails when asked for its events. It
stands in for the services that own the data: the booking source reads
``CARGOS``, the routing source ``ITINERARIES`` and the voyage and location
sources their own maps. Nothing reads these except through ``app.sources``,
which is what records the call. The handling events, the one mutable part,
live in ``app.handling.HandlingStore``.
"""
from __future__ import annotations

from datetime import UTC, datetime

import strawberry

from app.model import (
    Cargo,
    CarrierMovement,
    Itinerary,
    Leg,
    Location,
    RouteSpecification,
    TrackingId,
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



def _fault_cargo(tracking_id: str, description: str) -> Cargo:
    """A New York to Rotterdam cargo, booked with the ABC123 deadline."""
    return Cargo(
        id=strawberry.ID(f"cargo_{tracking_id}"),
        tracking_id=TrackingId(tracking_id),
        description=description,
        origin=NEW_YORK,
        destination=ROTTERDAM,
        route_specification=RouteSpecification(
            origin=NEW_YORK,
            destination=ROTTERDAM,
            arrival_deadline=_utc("2026-10-15T00:00:00+00:00"),
        ),
    )


def _one_leg_itinerary(voyage_number: str, load_un_locode: str) -> Itinerary:
    return Itinerary(
        legs=[
            Leg(
                voyage_number=voyage_number,
                load_un_locode=load_un_locode,
                unload_un_locode="NLRTM",
                load_time=V100S_DEPARTS,
                unload_time=V100S_ARRIVES,
            )
        ],
        final_arrival_date=V100S_ARRIVES,
    )


# JKL567: its one leg is on V404X; the voyage source fails for that number.
JKL567 = _fault_cargo("JKL567", "Machine parts")
# MNO901: its one leg loads at XXBAD, which the location source answers with None.
MNO901 = _fault_cargo("MNO901", "Textiles")
# PQR234: itinerary as ABC123; the handling source fails when it lists this cargo's events.
PQR234 = _fault_cargo("PQR234", "Coffee beans")

LOCATIONS = {loc.un_locode: loc for loc in (NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)}
VOYAGES = {voyage.number: voyage for voyage in (V100S, V200E, V300A)}
CARGOS = {cargo.tracking_id: cargo for cargo in (ABC123, XYZ789, JKL567, MNO901, PQR234)}
ITINERARIES = {
    ABC123.tracking_id: ABC123_ITINERARY,
    JKL567.tracking_id: _one_leg_itinerary("V404X", "USNYC"),
    MNO901.tracking_id: _one_leg_itinerary("V100S", "XXBAD"),
    PQR234.tracking_id: ABC123_ITINERARY,
}

