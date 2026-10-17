"""Ch15 Persisted queries and APQ - the Strawberry types (code-first).

The slice of the canonical tracking-view schema this chapter serves: scalars,
enums, the ``Node`` interface and the object types of the cargo graph. Every
type, field, nullability and description here mirrors
``contracts/schema/shipping/*.graphql``; verify.sh checks that against the
live introspection result.

A field that another service owns is a resolver method (``Cargo.itinerary``,
``Cargo.delivery``, ``Leg.voyage``, ``Leg.load_location``,
``Leg.unload_location``). Each is ``async def``: it awaits a source through the
request's ``TrackingContext``, so graphql-core can start sibling fields before
any of them finish.

Strawberry fields are non-null unless the annotation says ``| None``, and
snake_case names become camelCase on the wire (``un_locode`` is ``unLocode``).
"""
from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from enum import Enum
from typing import TYPE_CHECKING, Annotated, NewType

import strawberry
from strawberry import Info

from app import pagination
from app.context import TrackingContext

if TYPE_CHECKING:
    from app.handling import HandlingRecord


def _parse_string(value: object) -> str:
    """Accept only a JSON string for a string-based custom scalar.

    ``parse_value=str`` would coerce ``123`` to ``"123"``; the contract's
    scalars are strings, so any other input is a validation error (the same
    behavior as SmallRye's ``CustomStringScalar`` on the Quarkus side).
    """
    if not isinstance(value, str):
        raise ValueError(f"expected a string, got {type(value).__name__}")
    return value


def _serialize_datetime(value: datetime) -> str:
    """Output coercion: a UTC instant as ``YYYY-MM-DDTHH:MM:SSZ``, whole seconds."""
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_datetime(value: object) -> datetime:
    """Input coercion: an RFC 3339 string with an offset, normalised to UTC.

    A non-string, an unparsable string and a date-time without an offset (a
    naive value) are all rejected rather than guessed at.
    """
    if not isinstance(value, str):
        raise ValueError(f"expected a string, got {type(value).__name__}")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"not an RFC 3339 date-time: {value!r}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"a date-time must carry a UTC offset, such as Z: {value!r}")
    return parsed.astimezone(UTC)


# The custom scalars. Fields are annotated with the Python type (the two
# ``NewType`` strings and the plain ``datetime``); ``SCALAR_MAP``, passed to the
# schema through ``StrawberryConfig(scalar_map=...)`` in app/schema.py, maps
# each type to its GraphQL definition. For ``datetime`` that replaces
# Strawberry's built-in ``DateTime``, whose ``isoformat()`` output (``+00:00``)
# is not the contract's wire format.
TrackingId = NewType("TrackingId", str)
UnLocode = NewType("UnLocode", str)

SCALAR_MAP = {
    TrackingId: strawberry.scalar(
        name="TrackingId",
        description=(
            "A cargo tracking identifier issued at booking time, for example `ABC123`.\n"
            "Opaque to clients; compare for equality only."
        ),
        serialize=str,
        parse_value=_parse_string,
    ),
    UnLocode: strawberry.scalar(
        name="UnLocode",
        description=(
            "A UN/LOCODE port or terminal code: two letters of country plus three of\n"
            "location, for example `USNYC`, `NLRTM` or `SGSIN`."
        ),
        specified_by_url="https://unece.org/trade/uncefact/unlocode",
        serialize=str,
        parse_value=_parse_string,
    ),
    datetime: strawberry.scalar(
        name="DateTime",
        description="An RFC 3339 date-time in UTC, for example `2026-10-15T09:30:00Z`.",
        specified_by_url="https://www.rfc-editor.org/rfc/rfc3339",
        serialize=_serialize_datetime,
        parse_value=_parse_datetime,
    ),
}


@strawberry.enum(description="Where a cargo currently is relative to its plan.")
class TransportStatus(Enum):
    NOT_RECEIVED = strawberry.enum_value("NOT_RECEIVED", description="Booked but not yet received.")
    IN_PORT = strawberry.enum_value("IN_PORT", description="Received at origin and awaiting loading.")
    ONBOARD_CARRIER = strawberry.enum_value("ONBOARD_CARRIER", description="Aboard a vessel.")
    CLAIMED = strawberry.enum_value("CLAIMED", description="Handed over at the final destination.")
    UNKNOWN = strawberry.enum_value("UNKNOWN", description="Whereabouts unknown.")


@strawberry.enum(description="Whether the cargo is following its itinerary.")
class RoutingStatus(Enum):
    NOT_ROUTED = strawberry.enum_value("NOT_ROUTED", description="No itinerary has been assigned.")
    ROUTED = strawberry.enum_value(
        "ROUTED", description="The itinerary satisfies the route specification."
    )
    MISROUTED = strawberry.enum_value(
        "MISROUTED", description="The itinerary no longer satisfies the route specification."
    )


@strawberry.enum(description="The kind of handling a cargo underwent.")
class HandlingEventType(Enum):
    RECEIVE = strawberry.enum_value("RECEIVE", description="Received from the shipper at origin.")
    LOAD = strawberry.enum_value("LOAD", description="Loaded onto a vessel.")
    UNLOAD = strawberry.enum_value("UNLOAD", description="Unloaded from a vessel.")
    CUSTOMS = strawberry.enum_value("CUSTOMS", description="Cleared by customs.")
    CLAIM = strawberry.enum_value("CLAIM", description="Claimed by the consignee at destination.")


@strawberry.interface(
    description=(
        "A global object identifier, unique across the whole graph. Implements the\n"
        "Relay Global Object Identification contract used by `Query.node`."
    )
)
class Node:
    id: strawberry.ID = strawberry.field(
        description="The globally unique, opaque identifier of this object."
    )


@strawberry.type(description="A port or terminal, identified by its UN/LOCODE.")
class Location(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this location."
    )
    un_locode: UnLocode = strawberry.field(description="The UN/LOCODE, for example `NLRTM`.")
    name: str = strawberry.field(description="The human-readable name, for example `Rotterdam`.")
    country: str = strawberry.field(
        description="The ISO 3166-1 alpha-2 country code, for example `NL`."
    )


@strawberry.type(
    description="One scheduled departure-to-arrival movement of a voyage between two locations."
)
class CarrierMovement:
    departure_location: Location = strawberry.field(description="Where the movement departs from.")
    arrival_location: Location = strawberry.field(description="Where the movement arrives.")
    departure_time: datetime = strawberry.field(description="Scheduled departure time.")
    arrival_time: datetime = strawberry.field(description="Scheduled arrival time.")


@strawberry.type(description="A scheduled carrier movement made up of one or more legs.")
class Voyage(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this voyage."
    )
    number: str = strawberry.field(description="The carrier's voyage number, for example `V100S`.")
    schedule: list[CarrierMovement] = strawberry.field(
        description="The scheduled movements of this voyage in departure order."
    )


@strawberry.type(description="One hop of an itinerary on a single voyage.")
class Leg:
    # What the routing service returns: a voyage number and two UN/LOCODEs.
    # Private fields stay out of the schema; the three resolvers below turn
    # them into the objects the contract promises.
    voyage_number: strawberry.Private[str]
    load_un_locode: strawberry.Private[str]
    unload_un_locode: strawberry.Private[str]
    load_time: datetime = strawberry.field(description="When the cargo is loaded.")
    unload_time: datetime = strawberry.field(description="When the cargo is unloaded.")

    @strawberry.field(
        description="The voyage that carries this leg. Null when the voyage service is unavailable."
    )
    async def voyage(self, info: Info[TrackingContext]) -> Voyage | None:
        return await info.context.loaders.voyage.load(self.voyage_number)

    @strawberry.field(description="Where the cargo is loaded.")
    async def load_location(self, info: Info[TrackingContext]) -> Location:
        return await info.context.loaders.location.load(self.load_un_locode)

    @strawberry.field(description="Where the cargo is unloaded.")
    async def unload_location(self, info: Info[TrackingContext]) -> Location:
        return await info.context.loaders.location.load(self.unload_un_locode)


@strawberry.type(
    description="The planned sequence of legs moving a cargo from origin to destination."
)
class Itinerary:
    legs: list[Leg] = strawberry.field(
        description="Ordered legs of the route; never empty for an assigned itinerary."
    )
    final_arrival_time: datetime = strawberry.field(description="When the final leg arrives.")
    final_arrival_date: datetime = strawberry.field(
        description="When the final leg arrives.",
        deprecation_reason="Use `finalArrivalTime`.",
    )


@strawberry.type(description="The customer's routing requirements for a cargo.")
class RouteSpecification:
    origin: Location = strawberry.field(description="Required origin.")
    destination: Location = strawberry.field(description="Required destination.")
    arrival_deadline: datetime = strawberry.field(
        description="The date by which the cargo must arrive."
    )


@strawberry.type(description="An expected future handling of a cargo.")
class HandlingActivity:
    type: HandlingEventType = strawberry.field(description="The kind of handling expected.")
    location: Location = strawberry.field(description="Where it is expected.")
    voyage: Voyage | None = strawberry.field(
        description="On which voyage. Null for handling not tied to a voyage."
    )


@strawberry.type(description="The derived delivery state of a cargo.")
class Delivery:
    transport_status: TransportStatus = strawberry.field(description="Current transport status.")
    routing_status: RoutingStatus = strawberry.field(
        description="Whether the cargo follows its itinerary."
    )
    misdirected: bool = strawberry.field(
        description="True when the last handling event was off-itinerary."
    )
    last_known_location: Location | None = strawberry.field(
        description="Where the cargo was last handled. Null before the first handling event."
    )
    current_voyage: Voyage | None = strawberry.field(
        description="The voyage the cargo is on. Null unless aboard a carrier."
    )
    estimated_time_of_arrival: datetime | None = strawberry.field(
        description="Estimated arrival. Null when the estimate is unavailable."
    )
    next_expected_activity: HandlingActivity | None = strawberry.field(
        description="The next expected handling. Null when none is expected."
    )


@strawberry.type(
    description="A consignment of goods being shipped, tracked end to end by its tracking id."
)
class Cargo(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this cargo."
    )
    tracking_id: TrackingId = strawberry.field(description="The public tracking identifier.")
    description: str = strawberry.field(description="Free-text description of the goods.")
    origin: Location = strawberry.field(description="Where the cargo was booked from.")
    destination: Location = strawberry.field(description="Where the cargo is booked to.")
    route_specification: RouteSpecification = strawberry.field(
        description="What the customer asked for and the route must satisfy."
    )

    @strawberry.field(description="Delivery status derived from handling history.")
    async def delivery(self, info: Info[TrackingContext]) -> Delivery:
        # The two inputs are independent, so they are fetched together; the
        # derivation itself calls no source.
        itinerary, events = await asyncio.gather(
            info.context.loaders.itinerary.load(self.tracking_id),
            info.context.loaders.events.load(self.tracking_id),
        )
        return info.context.derivation.derive(self, itinerary, events)

    @strawberry.field(
        description="The planned route. Null until the routing service has assigned one."
    )
    async def itinerary(self, info: Info[TrackingContext]) -> Itinerary | None:
        return await info.context.loaders.itinerary.load(self.tracking_id)

    @strawberry.field(description="Handling events for this cargo, newest first, as a Relay connection.")
    async def handling_history(
        self,
        info: Info[TrackingContext],
        first: Annotated[
            strawberry.Maybe[int | None], strawberry.argument(description="Return the first N events.")
        ] = None,
        after: Annotated[
            strawberry.Maybe[str | None], strawberry.argument(description="Return events after this cursor.")
        ] = None,
        last: Annotated[
            strawberry.Maybe[int | None], strawberry.argument(description="Return the last N events.")
        ] = None,
        before: Annotated[
            strawberry.Maybe[str | None], strawberry.argument(description="Return events before this cursor.")
        ] = None,
    ) -> HandlingEventConnection:
        page = pagination.parse_page(
            pagination.argument(first),
            pagination.argument(after),
            pagination.argument(last),
            pagination.argument(before),
            pagination.decode_event,
        )
        events = await info.context.handling.page_events(self.tracking_id, page)
        edges = [
            HandlingEventEdge(cursor=pagination.encode_event(e.key), node=HandlingEvent.of(e))
            for e in events.items
        ]
        return HandlingEventConnection(
            edges=edges,
            page_info=PageInfo.of(events.has_next, events.has_previous, [e.cursor for e in edges]),
            total_count=events.total_count,
        )


@strawberry.type(description="A recorded handling of a cargo at a location, optionally on a voyage.")
class HandlingEvent(Node):
    # The stored event keeps the keys of what other services own; the three
    # resolvers below turn them into the objects the contract promises.
    un_locode: strawberry.Private[str]
    voyage_number: strawberry.Private[str | None]
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this event."
    )
    tracking_id: TrackingId = strawberry.field(
        description="The tracking id of the cargo that was handled."
    )
    type: HandlingEventType = strawberry.field(description="What kind of handling occurred.")
    completion_time: datetime = strawberry.field(
        description="When the handling actually happened."
    )
    registration_time: datetime = strawberry.field(
        description="When the event was registered in the system."
    )

    @classmethod
    def of(cls, record: HandlingRecord) -> HandlingEvent:
        return cls(
            id=strawberry.ID(record.id),
            tracking_id=TrackingId(record.tracking_id),
            type=record.type,
            un_locode=record.un_locode,
            voyage_number=record.voyage_number,
            completion_time=record.completion_time,
            registration_time=record.registration_time,
        )

    @strawberry.field(
        description="The cargo that was handled. Null when the cargo service is unavailable."
    )
    async def cargo(self, info: Info[TrackingContext]) -> Cargo | None:
        return await info.context.loaders.cargo.load(self.tracking_id)

    @strawberry.field(description="Where it occurred.")
    async def location(self, info: Info[TrackingContext]) -> Location:
        return await info.context.loaders.location.load(self.un_locode)

    @strawberry.field(description="The voyage involved. Null for RECEIVE, CUSTOMS and CLAIM.")
    async def voyage(self, info: Info[TrackingContext]) -> Voyage | None:
        if self.voyage_number is None:
            return None
        return await info.context.loaders.voyage.load(self.voyage_number)


@strawberry.type(
    description=(
        "Relay cursor-connection page metadata.\n"
        "See https://relay.dev/graphql/connections.htm"
    )
)
class PageInfo:
    has_next_page: bool = strawberry.field(
        description="True when more edges exist after `endCursor`."
    )
    has_previous_page: bool = strawberry.field(
        description="True when more edges exist before `startCursor`."
    )
    start_cursor: str | None = strawberry.field(
        description="Cursor of the first edge in this page; null when the page is empty."
    )
    end_cursor: str | None = strawberry.field(
        description="Cursor of the last edge in this page; null when the page is empty."
    )

    @classmethod
    def of(cls, has_next_page: bool, has_previous_page: bool, cursors: list[str]) -> PageInfo:
        """The metadata of a page whose edges carry ``cursors``, in order."""
        return cls(
            has_next_page=has_next_page,
            has_previous_page=has_previous_page,
            start_cursor=cursors[0] if cursors else None,
            end_cursor=cursors[-1] if cursors else None,
        )


@strawberry.type(description="A cargo and its cursor.")
class CargoEdge:
    # The edge holds the key of the cargo it points at. ``node`` loads the cargo
    # from the booking source when a query selects it, so an edge whose cargo
    # cannot be loaded fails alone.
    tracking_id: strawberry.Private[str]
    cursor: str = strawberry.field(description="An opaque cursor for this edge.")

    @strawberry.field(
        description=(
            "The cargo at this edge. Null when the cargo failed to resolve, "
            "so one bad item nulls its edge instead of the whole page."
        )
    )
    async def node(self, info: Info[TrackingContext]) -> Cargo | None:
        return await info.context.loaders.cargo.load(self.tracking_id)


@strawberry.type(description="A Relay connection of cargos.")
class CargoConnection:
    edges: list[CargoEdge] = strawberry.field(description="The edges in this page.")
    page_info: PageInfo = strawberry.field(description="Pagination metadata.")
    total_count: int | None = strawberry.field(
        description="Total matching cargos. Null when counting is too expensive."
    )


@strawberry.type(description="A handling event and its cursor.")
class HandlingEventEdge:
    cursor: str = strawberry.field(description="An opaque cursor for this edge.")
    node: HandlingEvent | None = strawberry.field(
        description=(
            "The event at this edge. Null when the event failed to resolve, "
            "so one bad item nulls its edge instead of the whole page."
        )
    )


@strawberry.type(description="A Relay connection of handling events.")
class HandlingEventConnection:
    edges: list[HandlingEventEdge] = strawberry.field(description="The edges in this page.")
    page_info: PageInfo = strawberry.field(description="Pagination metadata.")
    total_count: int | None = strawberry.field(
        description="Total events for the cargo. Null when counting is too expensive."
    )


@strawberry.enum(description="Machine-readable reasons a mutation input was rejected.")
class UserErrorCode(Enum):
    UNKNOWN_CARGO = strawberry.enum_value(
        "UNKNOWN_CARGO", description="No cargo exists with the given tracking id."
    )
    UNKNOWN_LOCATION = strawberry.enum_value(
        "UNKNOWN_LOCATION", description="No location exists with the given UN/LOCODE."
    )
    UNKNOWN_VOYAGE = strawberry.enum_value(
        "UNKNOWN_VOYAGE", description="No voyage exists with the given voyage number."
    )
    VOYAGE_REQUIRED = strawberry.enum_value(
        "VOYAGE_REQUIRED", description="LOAD and UNLOAD events must name a voyage."
    )
    VOYAGE_NOT_ALLOWED = strawberry.enum_value(
        "VOYAGE_NOT_ALLOWED",
        description="RECEIVE, CUSTOMS and CLAIM events must not name a voyage.",
    )
    INVALID_COMPLETION_TIME = strawberry.enum_value(
        "INVALID_COMPLETION_TIME",
        description="The completion time is in the future or otherwise invalid.",
    )


@strawberry.type(description="A domain validation failure returned as data, not as a top-level error.")
class UserError:
    code: UserErrorCode = strawberry.field(description="A stable machine-readable code.")
    message: str = strawberry.field(description="A human-readable explanation.")
    field: list[str] | None = strawberry.field(
        description=(
            'Path to the input field the error concerns, for example `["input", "voyageNumber"]`. '
            "Null when it concerns the whole input."
        )
    )


@strawberry.input(description="Input for `Mutation.registerHandlingEvent`.")
class RegisterHandlingEventInput:
    tracking_id: TrackingId = strawberry.field(description="The cargo that was handled.")
    type: HandlingEventType = strawberry.field(description="What kind of handling occurred.")
    location: UnLocode = strawberry.field(description="Where it occurred.")
    # Optional input fields are strawberry.Maybe: an absent field arrives as
    # None, a sent value as Some(value), and the SDL prints neither a default
    # nor "= null" (a plain `str | None = None` prints `= null`).
    voyage_number: strawberry.Maybe[str | None] = strawberry.field(
        description="The voyage number; required for LOAD and UNLOAD, forbidden otherwise."
    )
    completion_time: datetime = strawberry.field(
        description="When the handling actually happened."
    )
    idempotency_key: strawberry.Maybe[str | None] = strawberry.field(
        description=(
            "Client-supplied key making retries safe: a repeated request with the same key "
            "returns the originally recorded event instead of recording a second one."
        )
    )


@strawberry.type(description="Result of `Mutation.registerHandlingEvent`.")
class RegisterHandlingEventPayload:
    handling_event: HandlingEvent | None = strawberry.field(
        description="The recorded event. Null when `userErrors` is non-empty."
    )
    cargo: Cargo | None = strawberry.field(
        description="The cargo with its delivery state recomputed. Null when `userErrors` is non-empty."
    )
    user_errors: list[UserError] = strawberry.field(
        description=(
            "Domain validation failures returned as data; empty on success. "
            "Distinct from the response's top-level `errors`."
        )
    )
