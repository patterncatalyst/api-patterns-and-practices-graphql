"""Ch0 prerequisites SKELETON - the Strawberry schema (code-first).

The slice of the canonical tracking-view schema this chapter serves:
``Query.cargo(trackingId: TrackingId!): Cargo`` returning one canned cargo.
Every type, field, nullability and description here mirrors
``contracts/schema/shipping/*.graphql``; verify.sh checks that against the
live introspection result.
"""
from __future__ import annotations

from typing import Annotated, NewType

import strawberry
from strawberry.schema.config import StrawberryConfig


def _parse_string(value: object) -> str:
    """Accept only a JSON string for a string-based custom scalar.

    ``parse_value=str`` would coerce ``123`` to ``"123"``; the contract's
    scalars are strings, so any other input is a validation error (the same
    behavior as SmallRye's ``CustomStringScalar`` on the Quarkus side).
    """
    if not isinstance(value, str):
        raise ValueError(f"expected a string, got {type(value).__name__}")
    return value


# The custom scalars: fields are annotated with the two ``NewType`` strings,
# and ``SCALAR_MAP`` (passed through ``StrawberryConfig(scalar_map=...)``)
# maps each one to its GraphQL definition.
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
}


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


NEW_YORK = Location(
    id=strawberry.ID("loc_USNYC"), un_locode=UnLocode("USNYC"), name="New York", country="US"
)
ROTTERDAM = Location(
    id=strawberry.ID("loc_NLRTM"), un_locode=UnLocode("NLRTM"), name="Rotterdam", country="NL"
)
ABC123 = Cargo(
    id=strawberry.ID("cargo_ABC123"),
    tracking_id=TrackingId("ABC123"),
    description="Palletized electronics",
    origin=NEW_YORK,
    destination=ROTTERDAM,
)


@strawberry.type(
    description="The tracking view: read-oriented aggregation of cargo, routing and handling data."
)
class Query:
    @strawberry.field(
        description="Look up one cargo by its tracking id. Null when no such cargo exists."
    )
    def cargo(
        self,
        tracking_id: Annotated[
            TrackingId,
            strawberry.argument(name="trackingId", description="The tracking id issued at booking."),
        ],
    ) -> Cargo | None:
        return ABC123 if tracking_id == ABC123.tracking_id else None


schema = strawberry.Schema(query=Query, config=StrawberryConfig(scalar_map=SCALAR_MAP))
