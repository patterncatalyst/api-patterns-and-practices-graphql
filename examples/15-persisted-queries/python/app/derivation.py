"""Ch15 Persisted queries and APQ - deriving ``Delivery`` from handling events.

``DeliveryDerivation.derive`` takes the booking record, the itinerary (or
``None``) and the handling events, and returns a ``Delivery``. It calls no
source, so it can be tested without a request. ``Cargo.delivery`` in
``app/model.py`` fetches the inputs through the request's sources and hands
them to the derivation on ``info.context``.

The rules, with "last event" meaning the maximum completion time (a tie goes
to the later registration):

================  ===============  ==============  ===================================
last event        transport        current voyage  next expected activity
================  ===============  ==============  ===================================
none              NOT_RECEIVED     none            RECEIVE at the route's origin
RECEIVE           IN_PORT          none            LOAD on the first leg
LOAD at L on V    ONBOARD_CARRIER  V               UNLOAD at the matching leg's end
UNLOAD at L on V  IN_PORT          none            CLAIM at L if L is the destination,
                                                   else LOAD on the next leg
CUSTOMS           IN_PORT          none            none
CLAIM             CLAIMED          none            none
================  ===============  ==============  ===================================

An activity that needs a leg the itinerary does not have is ``None``.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence

from app.handling import HandlingRecord
from app.model import (
    Cargo,
    Delivery,
    HandlingActivity,
    HandlingEventType,
    Itinerary,
    Leg,
    Location,
    RoutingStatus,
    TransportStatus,
    Voyage,
)


class DeliveryDerivation:
    """Turns booking, routing and handling facts into a ``Delivery``.

    ``locations`` and ``voyages`` are the reference data the result embeds
    (the same objects ``Query.location`` and ``Query.voyage`` serve), keyed by
    UN/LOCODE and voyage number.
    """

    def __init__(self, locations: Mapping[str, Location], voyages: Mapping[str, Voyage]) -> None:
        self._locations = locations
        self._voyages = voyages

    def derive(
        self, cargo: Cargo, itinerary: Itinerary | None, events: Sequence[HandlingRecord]
    ) -> Delivery:
        spec = cargo.route_specification
        legs = itinerary.legs if itinerary else []
        last = max(events, key=lambda e: (e.completion_time, e.registration_time), default=None)

        routing_status = _routing_status(spec.origin.un_locode, spec.destination.un_locode, legs)
        misdirected = (
            routing_status is not RoutingStatus.NOT_ROUTED
            and last is not None
            and last.type in (HandlingEventType.LOAD, HandlingEventType.UNLOAD)
            and _matching_leg(legs, last) is None
        )
        on_course = routing_status is RoutingStatus.ROUTED and not misdirected

        return Delivery(
            transport_status=_transport_status(last),
            routing_status=routing_status,
            misdirected=misdirected,
            last_known_location=self._locations[last.un_locode] if last else None,
            current_voyage=(
                self._voyage(last.voyage_number)
                if last and last.type is HandlingEventType.LOAD
                else None
            ),
            estimated_time_of_arrival=(
                itinerary.final_arrival_time if itinerary and on_course else None
            ),
            next_expected_activity=self._next_activity(cargo, legs, last),
        )

    def _next_activity(
        self, cargo: Cargo, legs: Sequence[Leg], last: HandlingRecord | None
    ) -> HandlingActivity | None:
        destination = cargo.route_specification.destination.un_locode
        if last is None:
            return HandlingActivity(
                type=HandlingEventType.RECEIVE,
                location=cargo.route_specification.origin,
                voyage=None,
            )
        match last.type:
            case HandlingEventType.RECEIVE:
                return self._load(legs[0]) if legs else None
            case HandlingEventType.LOAD:
                index = _matching_leg(legs, last)
                return None if index is None else self._unload(legs[index])
            case HandlingEventType.UNLOAD:
                if last.un_locode == destination:
                    return HandlingActivity(
                        type=HandlingEventType.CLAIM,
                        location=self._locations[last.un_locode],
                        voyage=None,
                    )
                index = _matching_leg(legs, last)
                if index is None or index + 1 >= len(legs):
                    return None
                return self._load(legs[index + 1])
            case _:
                return None

    def _load(self, leg: Leg) -> HandlingActivity:
        return HandlingActivity(
            type=HandlingEventType.LOAD,
            location=self._locations[leg.load_un_locode],
            voyage=self._voyage(leg.voyage_number),
        )

    def _unload(self, leg: Leg) -> HandlingActivity:
        return HandlingActivity(
            type=HandlingEventType.UNLOAD,
            location=self._locations[leg.unload_un_locode],
            voyage=self._voyage(leg.voyage_number),
        )

    def _voyage(self, number: str | None) -> Voyage | None:
        return self._voyages.get(number) if number else None


def _transport_status(last: HandlingRecord | None) -> TransportStatus:
    if last is None:
        return TransportStatus.NOT_RECEIVED
    match last.type:
        case HandlingEventType.LOAD:
            return TransportStatus.ONBOARD_CARRIER
        case HandlingEventType.CLAIM:
            return TransportStatus.CLAIMED
        case _:
            return TransportStatus.IN_PORT


def _routing_status(origin: str, destination: str, legs: Sequence[Leg]) -> RoutingStatus:
    if not legs:
        return RoutingStatus.NOT_ROUTED
    if legs[0].load_un_locode != origin or legs[-1].unload_un_locode != destination:
        return RoutingStatus.MISROUTED
    return RoutingStatus.ROUTED


def _matching_leg(legs: Sequence[Leg], event: HandlingRecord) -> int | None:
    """The index of the leg a LOAD or UNLOAD belongs to: same place, same voyage."""
    for index, leg in enumerate(legs):
        place = leg.load_un_locode if event.type is HandlingEventType.LOAD else leg.unload_un_locode
        if place == event.un_locode and leg.voyage_number == event.voyage_number:
            return index
    return None
