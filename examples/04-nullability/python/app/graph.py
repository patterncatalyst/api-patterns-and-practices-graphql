"""Ch4 Nullability and null propagation - the types whose fields call sources.

``Leg`` stores the keys of what it refers to (``Private`` fields are not part
of the schema) and resolves ``voyage``, ``load_location`` and
``unload_location`` through the sources. ``Cargo.delivery`` is a resolver over
the delivery source. What each source does (answer, return ``None``, raise)
and how the field is typed (``| None`` or not) decide what the response holds.
"""
from __future__ import annotations

from datetime import datetime

import strawberry

from app.model import (
    Delivery,
    Location,
    Node,
    RouteSpecification,
    TrackingId,
    Voyage,
)
from app.sources import delivery_source, location_source, voyage_source


@strawberry.type(description="One hop of an itinerary on a single voyage.")
class Leg:
    voyage_number: strawberry.Private[str]
    load_un_locode: strawberry.Private[str]
    unload_un_locode: strawberry.Private[str]
    load_time: datetime = strawberry.field(description="When the cargo is loaded.")
    unload_time: datetime = strawberry.field(description="When the cargo is unloaded.")

    @strawberry.field(
        description="The voyage that carries this leg. Null when the voyage service is unavailable."
    )
    def voyage(self) -> Voyage | None:
        return voyage_source.get_voyage(self.voyage_number)

    @strawberry.field(description="Where the cargo is loaded.")
    def load_location(self) -> Location:
        # The source returns None for a code it does not know. The field is
        # non-null, so graphql-core turns that None into an execution error.
        return location_source.get_location(self.load_un_locode)

    @strawberry.field(description="Where the cargo is unloaded.")
    def unload_location(self) -> Location:
        return location_source.get_location(self.unload_un_locode)


@strawberry.type(
    description="The planned sequence of legs moving a cargo from origin to destination."
)
class Itinerary:
    legs: list[Leg] = strawberry.field(
        description="Ordered legs of the route; never empty for an assigned itinerary."
    )
    final_arrival_date: datetime = strawberry.field(description="When the final leg arrives.")


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
    itinerary: Itinerary | None = strawberry.field(
        description="The planned route. Null until the routing service has assigned one."
    )

    @strawberry.field(description="Delivery status derived from handling history.")
    def delivery(self) -> Delivery:
        return delivery_source.get_delivery(self.tracking_id)
