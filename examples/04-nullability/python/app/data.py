"""Ch4 Nullability and null propagation - the cargo seed.

Five cargos over the locations and voyages in ``app/sources.py``, the same
data on both stacks. ``ABC123`` and ``XYZ789`` are healthy. The other three
carry one fault each, found by the sources rather than stored in the cargo:

* ``JKL567``: its one leg is on voyage ``V404X``, and the voyage source raises;
* ``MNO901``: its one leg loads at ``XXBAD``, a code the location source does
  not know, so it returns ``None``;
* ``PQR234``: a healthy itinerary, and the delivery source raises.

A ``Leg`` holds the keys of its voyage and locations; every object is
reachable by its global id through ``NODES``.
"""
from __future__ import annotations

import strawberry

from app.graph import Cargo, Itinerary, Leg
from app.model import Node, RouteSpecification, TrackingId
from app.sources import (
    FAULT_UNLOADS,
    HAMBURG,
    LOCATIONS,
    NEW_YORK,
    ROTTERDAM,
    SINGAPORE,
    V100S_ARRIVES,
    V100S_DEPARTS,
    V200E_ARRIVES,
    V200E_DEPARTS,
    VOYAGES,
    utc,
)

FAULT_LOADS = utc("2026-10-20T08:00:00+00:00")
FAULT_DEADLINE = utc("2026-11-15T00:00:00+00:00")

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


def _one_leg_itinerary(voyage_number: str, load_un_locode: str) -> Itinerary:
    return Itinerary(
        legs=[
            Leg(
                voyage_number=voyage_number,
                load_un_locode=load_un_locode,
                unload_un_locode="NLRTM",
                load_time=FAULT_LOADS,
                unload_time=FAULT_UNLOADS,
            )
        ],
        final_arrival_date=FAULT_UNLOADS,
    )


def _fault_cargo(tracking_id: str, description: str, itinerary: Itinerary) -> Cargo:
    return Cargo(
        id=strawberry.ID(f"cargo_{tracking_id}"),
        tracking_id=TrackingId(tracking_id),
        description=description,
        origin=NEW_YORK,
        destination=ROTTERDAM,
        route_specification=RouteSpecification(
            origin=NEW_YORK, destination=ROTTERDAM, arrival_deadline=FAULT_DEADLINE
        ),
        itinerary=itinerary,
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
        arrival_deadline=utc("2026-10-15T00:00:00+00:00"),
    ),
    itinerary=ABC123_ITINERARY,
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
        arrival_deadline=utc("2026-11-20T00:00:00+00:00"),
    ),
    itinerary=None,
)

JKL567 = _fault_cargo("JKL567", "Machine parts", _one_leg_itinerary("V404X", "USNYC"))
MNO901 = _fault_cargo("MNO901", "Textiles", _one_leg_itinerary("V100S", "XXBAD"))
PQR234 = _fault_cargo("PQR234", "Coffee beans", ABC123_ITINERARY)

CARGOS = {cargo.tracking_id: cargo for cargo in (ABC123, XYZ789, JKL567, MNO901, PQR234)}
NODES: dict[str, Node] = {
    node.id: node for group in (LOCATIONS, VOYAGES, CARGOS) for node in group.values()
}
