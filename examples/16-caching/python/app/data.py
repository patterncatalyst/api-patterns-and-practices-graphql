"""Ch16 Caching - the in-memory seed.

Five locations, three voyages and six cargos, the same data on both stacks.
The booking service keeps an index of its cargos, newest booking first, with
the routing status it stored for each; ``BOOKING_INDEX`` is that index, and the
booking source pages it. One cargo is a fault seed: the booking service cannot
load ``GHI345`` (see ``BookingSource.get_cargo``), although its index still
lists it. The data stands in for the services that own it: the booking source
reads ``CARGOS`` and ``BOOKING_INDEX``, the routing source ``ITINERARIES`` and
the voyage and location sources their own maps. Nothing reads these except
through ``app.sources``, which is what records the call. The handling events,
the one mutable part, live in ``app.handling.HandlingStore``.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

import strawberry

from app.model import (
    Cargo,
    CarrierMovement,
    Itinerary,
    Leg,
    Location,
    RouteSpecification,
    RoutingStatus,
    TrackingId,
    UnLocode,
    Voyage,
)
from app.pagination import CargoKey


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
V300A_DEPARTS = _utc("2026-11-02T04:00:00+00:00")
V300A_ARRIVES = _utc("2026-11-06T10:00:00+00:00")

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
        departure_time=V300A_DEPARTS,
        arrival_time=V300A_ARRIVES,
    ),
)

def _cargo(
    tracking_id: str, description: str, origin: Location, destination: Location, deadline: str
) -> Cargo:
    return Cargo(
        id=strawberry.ID(f"cargo_{tracking_id}"),
        tracking_id=TrackingId(tracking_id),
        description=description,
        origin=origin,
        destination=destination,
        route_specification=RouteSpecification(
            origin=origin, destination=destination, arrival_deadline=_utc(deadline)
        ),
    )


def _leg(voyage: str, load: str, unload: str, load_time: datetime, unload_time: datetime) -> Leg:
    return Leg(
        voyage_number=voyage,
        load_un_locode=load,
        unload_un_locode=unload,
        load_time=load_time,
        unload_time=unload_time,
    )


def _itinerary(final_arrival: datetime, *legs: Leg) -> Itinerary:
    """Both final-arrival fields carry the same instant: the old name is deprecated, not different."""
    return Itinerary(
        legs=list(legs), final_arrival_time=final_arrival, final_arrival_date=final_arrival
    )


# The two-leg New York to Rotterdam route of ABC123 and DEF456.
VIA_HAMBURG = _itinerary(
    V200E_ARRIVES,
    _leg("V100S", "USNYC", "DEHAM", V100S_DEPARTS, V100S_ARRIVES),
    _leg("V200E", "DEHAM", "NLRTM", V200E_DEPARTS, V200E_ARRIVES),
)
# The one-leg Singapore to Shanghai route of VWX901 and STU678.
SINGAPORE_TO_SHANGHAI = _itinerary(
    V300A_ARRIVES, _leg("V300A", "SGSIN", "CNSHA", V300A_DEPARTS, V300A_ARRIVES)
)

ABC123 = _cargo("ABC123", "Palletized electronics", NEW_YORK, ROTTERDAM, "2026-10-15T00:00:00+00:00")
DEF456 = _cargo("DEF456", "Auto parts", NEW_YORK, ROTTERDAM, "2026-10-15T00:00:00+00:00")
GHI345 = _cargo("GHI345", "Medical supplies", NEW_YORK, HAMBURG, "2026-10-20T00:00:00+00:00")
STU678 = _cargo("STU678", "Rubber goods", SINGAPORE, ROTTERDAM, "2026-11-20T00:00:00+00:00")
VWX901 = _cargo("VWX901", "Furniture", SINGAPORE, SHANGHAI, "2026-11-10T00:00:00+00:00")
XYZ789 = _cargo("XYZ789", "Frozen seafood", SINGAPORE, ROTTERDAM, "2026-11-20T00:00:00+00:00")


@dataclass(frozen=True, slots=True)
class BookingEntry:
    """One row of the booking index: what the booking service can list without
    loading the cargo. ``routing_status`` is the value the service stored at
    booking; verify.sh checks that it equals the derived one."""

    tracking_id: str
    booked_at: datetime
    routing_status: RoutingStatus

    @property
    def key(self) -> CargoKey:
        """The position of this row in the connection order."""
        return CargoKey(self.booked_at, self.tracking_id)


LOCATIONS = {loc.un_locode: loc for loc in (NEW_YORK, ROTTERDAM, HAMBURG, SINGAPORE, SHANGHAI)}
VOYAGES = {voyage.number: voyage for voyage in (V100S, V200E, V300A)}
CARGOS = {cargo.tracking_id: cargo for cargo in (ABC123, DEF456, GHI345, STU678, VWX901, XYZ789)}
ITINERARIES = {
    ABC123.tracking_id: VIA_HAMBURG,
    DEF456.tracking_id: VIA_HAMBURG,
    STU678.tracking_id: SINGAPORE_TO_SHANGHAI,
    VWX901.tracking_id: SINGAPORE_TO_SHANGHAI,
}

# The booking index, newest booking first.
BOOKING_INDEX = sorted(
    (
        BookingEntry("VWX901", _utc("2026-09-29T09:00:00+00:00"), RoutingStatus.ROUTED),
        BookingEntry("XYZ789", _utc("2026-09-28T09:00:00+00:00"), RoutingStatus.NOT_ROUTED),
        BookingEntry("STU678", _utc("2026-09-27T09:00:00+00:00"), RoutingStatus.MISROUTED),
        BookingEntry("DEF456", _utc("2026-09-26T09:00:00+00:00"), RoutingStatus.ROUTED),
        BookingEntry("ABC123", _utc("2026-09-25T09:00:00+00:00"), RoutingStatus.ROUTED),
        BookingEntry("GHI345", _utc("2026-09-24T09:00:00+00:00"), RoutingStatus.NOT_ROUTED),
    ),
    key=lambda entry: entry.key,
    reverse=True,
)
