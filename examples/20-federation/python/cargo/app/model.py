"""Ch20 Federation - the cargo subgraph's Strawberry types (code-first).

The part of the canonical tracking-view schema that the cargo subgraph owns:
scalars, the ``Node`` interface, and the object types of the cargo graph.
``Cargo``, ``Location`` and ``Voyage`` are federation entities: their keys
(``trackingId``, ``unLocode``, ``number``) let a gateway ask this subgraph for
an object when another subgraph names it, and ``resolve_reference`` is the
method that answers. The handling subgraph owns ``Cargo.delivery`` and
``Cargo.handlingHistory``. Every type, field, nullability and description here
mirrors ``contracts/schema/shipping/*.graphql``.

A field that another service owns is a resolver method (``Cargo.itinerary``,
``Leg.voyage``, ``Leg.load_location``, ``Leg.unload_location``). Each is
``async def``: it awaits a source through the request's ``TrackingContext``, so
graphql-core can start sibling fields before any of them finish.

Strawberry fields are non-null unless the annotation says ``| None``, and
snake_case names become camelCase on the wire (``un_locode`` is ``unLocode``).
"""
from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import NewType

import strawberry
from strawberry import Info

from app.context import TrackingContext


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


@strawberry.enum(description="Whether the cargo is following its itinerary.")
class RoutingStatus(Enum):
    NOT_ROUTED = strawberry.enum_value("NOT_ROUTED", description="No itinerary has been assigned.")
    ROUTED = strawberry.enum_value(
        "ROUTED", description="The itinerary satisfies the route specification."
    )
    MISROUTED = strawberry.enum_value(
        "MISROUTED", description="The itinerary no longer satisfies the route specification."
    )


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


@strawberry.federation.type(
    keys=["unLocode"], description="A port or terminal, identified by its UN/LOCODE."
)
class Location(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this location."
    )
    un_locode: UnLocode = strawberry.field(description="The UN/LOCODE, for example `NLRTM`.")
    name: str = strawberry.field(description="The human-readable name, for example `Rotterdam`.")
    country: str = strawberry.field(
        description="The ISO 3166-1 alpha-2 country code, for example `NL`."
    )

    @classmethod
    async def resolve_reference(
        cls, info: Info[TrackingContext], unLocode: UnLocode
    ) -> Location | None:
        """The entity resolver, through the request's location loader."""
        return await info.context.loaders.location.load(unLocode)


@strawberry.type(
    description="One scheduled departure-to-arrival movement of a voyage between two locations."
)
class CarrierMovement:
    departure_location: Location = strawberry.field(description="Where the movement departs from.")
    arrival_location: Location = strawberry.field(description="Where the movement arrives.")
    departure_time: datetime = strawberry.field(description="Scheduled departure time.")
    arrival_time: datetime = strawberry.field(description="Scheduled arrival time.")


@strawberry.federation.type(
    keys=["number"], description="A scheduled carrier movement made up of one or more legs."
)
class Voyage(Node):
    id: strawberry.ID = strawberry.field(
        description="The globally unique identifier of this voyage."
    )
    number: str = strawberry.field(description="The carrier's voyage number, for example `V100S`.")
    schedule: list[CarrierMovement] = strawberry.field(
        description="The scheduled movements of this voyage in departure order."
    )

    @classmethod
    async def resolve_reference(cls, info: Info[TrackingContext], number: str) -> Voyage | None:
        """The entity resolver, through the request's voyage loader."""
        return await info.context.loaders.voyage.load(number)


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


@strawberry.federation.type(
    keys=["trackingId"],
    description="A consignment of goods being shipped, tracked end to end by its tracking id.",
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

    @classmethod
    async def resolve_reference(
        cls, info: Info[TrackingContext], trackingId: TrackingId
    ) -> Cargo | None:
        """The entity resolver: ``_entities`` calls it once per representation.
        The parameter is named as the key is on the wire, because the representation's
        keys arrive as keyword arguments.

        Every call goes through the request's cargo loader, so the
        representations of one ``_entities`` request share one bulk booking call."""
        return await info.context.loaders.cargo.load(trackingId)

    @strawberry.field(
        description="The planned route. Null until the routing service has assigned one."
    )
    async def itinerary(self, info: Info[TrackingContext]) -> Itinerary | None:
        return await info.context.loaders.itinerary.load(self.tracking_id)


@strawberry.federation.type(
    shareable=True,
    description=(
        "Relay cursor-connection page metadata.\n"
        "See https://relay.dev/graphql/connections.htm"
    ),
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
