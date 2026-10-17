"""Ch8 Mutations and input types - the root fields and the schema.

``Query`` has four root fields: ``cargo``, ``location``, ``voyage`` and
``node``; ``Mutation`` has one, ``registerHandlingEvent``. Each is ``async def``
and reads or writes through the request's ``TrackingContext``. The types (and the resolvers on them) live in
``app/model.py``, the seed in ``app/data.py``.
"""
from __future__ import annotations

from typing import Annotated

import strawberry
from strawberry import Info
from strawberry.schema.config import StrawberryConfig

from app.context import TrackingContext
from app import registration
from app.model import (
    SCALAR_MAP,
    Cargo,
    HandlingEvent,
    Location,
    Node,
    RegisterHandlingEventInput,
    RegisterHandlingEventPayload,
    TrackingId,
    UnLocode,
    Voyage,
)


@strawberry.type(
    description="The tracking view: read-oriented aggregation of cargo, routing and handling data."
)
class Query:
    @strawberry.field(
        description="Look up one cargo by its tracking id. Null when no such cargo exists."
    )
    async def cargo(
        self,
        info: Info[TrackingContext],
        tracking_id: Annotated[
            TrackingId,
            strawberry.argument(name="trackingId", description="The tracking id issued at booking."),
        ],
    ) -> Cargo | None:
        return await info.context.booking.get_cargo(tracking_id)

    @strawberry.field(description="Look up a location by UN/LOCODE. Null when unknown.")
    async def location(
        self,
        info: Info[TrackingContext],
        un_locode: Annotated[
            UnLocode,
            strawberry.argument(
                name="unLocode", description="The UN/LOCODE to look up, for example `NLRTM`."
            ),
        ],
    ) -> Location | None:
        return await info.context.location.get_location(un_locode)

    @strawberry.field(description="Look up a voyage by voyage number. Null when unknown.")
    async def voyage(
        self,
        info: Info[TrackingContext],
        voyage_number: Annotated[
            str,
            strawberry.argument(
                name="voyageNumber", description="The carrier's voyage number, for example `V100S`."
            ),
        ],
    ) -> Voyage | None:
        return await info.context.voyage.get_voyage(voyage_number)

    @strawberry.field(
        description="Fetch any object by its global id (Relay Global Object Identification)."
    )
    async def node(
        self,
        info: Info[TrackingContext],
        id_: Annotated[
            strawberry.ID,
            strawberry.argument(name="id", description="The global id of the object to fetch."),
        ],
    ) -> Node | None:
        kind, _, key = id_.partition("_")
        match kind:
            case "cargo":
                return await info.context.booking.get_cargo(key)
            case "loc":
                return await info.context.location.get_location(key)
            case "voy":
                return await info.context.voyage.get_voyage(key)
            case "evt":
                record = await info.context.handling.get_event(id_)
                return HandlingEvent.of(record) if record else None
            case _:
                return None


@strawberry.type(
    description="The write surface; deliberately small because writes belong to the owning services."
)
class Mutation:
    @strawberry.mutation(
        description="Record that a cargo was handled. Domain failures are returned in `userErrors`."
    )
    async def register_handling_event(
        self,
        info: Info[TrackingContext],
        input_: Annotated[
            RegisterHandlingEventInput,
            strawberry.argument(name="input", description="The handling to record."),
        ],
    ) -> RegisterHandlingEventPayload:
        return await registration.register(info.context, input_)


schema = strawberry.Schema(query=Query, mutation=Mutation, config=StrawberryConfig(scalar_map=SCALAR_MAP))
