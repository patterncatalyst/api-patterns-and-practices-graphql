"""Ch20 Federation, handling subgraph - the in-memory seed.

The places and voyages this subgraph knows by key, and the booking and routing
facts the delivery derivation and the registration rules read. The cargo
subgraph holds the same six cargos, five locations and three voyages with all
their fields; this subgraph keeps the keys and the route facts. The data stands
in for the booking and routing services that both subgraphs read, and nothing
reads it except through ``app.sources``, which is what records the call. One
cargo is a fault seed: the booking service cannot load ``GHI345`` (see
``BookingSource.get_cargo``). The handling events, the one mutable part, live in
``app.handling.HandlingStore``.
"""
from __future__ import annotations

from datetime import UTC, datetime

from app.model import (
    Cargo,
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


def _location(un_locode: str) -> Location:
    return Location(un_locode=UnLocode(un_locode))


NEW_YORK = _location("USNYC")
ROTTERDAM = _location("NLRTM")
HAMBURG = _location("DEHAM")
SINGAPORE = _location("SGSIN")
SHANGHAI = _location("CNSHA")

V100S_DEPARTS = _utc("2026-10-01T08:00:00+00:00")
V100S_ARRIVES = _utc("2026-10-09T14:00:00+00:00")
V200E_DEPARTS = _utc("2026-10-10T06:00:00+00:00")
V200E_ARRIVES = _utc("2026-10-11T18:00:00+00:00")
V300A_DEPARTS = _utc("2026-11-02T04:00:00+00:00")
V300A_ARRIVES = _utc("2026-11-06T10:00:00+00:00")


def _cargo(tracking_id: str, origin: Location, destination: Location) -> Cargo:
    return Cargo(
        tracking_id=TrackingId(tracking_id),
        route_specification=RouteSpecification(origin=origin, destination=destination),
    )


# The two-leg New York to Rotterdam route of ABC123 and DEF456.
VIA_HAMBURG = Itinerary(
    legs=[
        Leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
        Leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES),
    ],
    final_arrival_time=V200E_ARRIVES,
)
# The one-leg Singapore to Shanghai route of VWX901 and STU678.
SINGAPORE_TO_SHANGHAI = Itinerary(
    legs=[Leg("V300A", "SGSIN", "CNSHA", V300A_DEPARTS, V300A_ARRIVES)],
    final_arrival_time=V300A_ARRIVES,
)

LOCATIONS = {loc.un_locode: loc for loc in (NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)}
VOYAGES = {number: Voyage(number=number) for number in ("V100S", "V200E", "V300A")}
CARGOS = {
    cargo.tracking_id: cargo
    for cargo in (
        _cargo("ABC123", NEW_YORK, ROTTERDAM),
        _cargo("DEF456", NEW_YORK, ROTTERDAM),
        _cargo("GHI345", NEW_YORK, HAMBURG),
        _cargo("STU678", SINGAPORE, ROTTERDAM),
        _cargo("VWX901", SINGAPORE, SHANGHAI),
        _cargo("XYZ789", SINGAPORE, ROTTERDAM),
    )
}
ITINERARIES = {
    "ABC123": VIA_HAMBURG,
    "DEF456": VIA_HAMBURG,
    "STU678": SINGAPORE_TO_SHANGHAI,
    "VWX901": SINGAPORE_TO_SHANGHAI,
}
