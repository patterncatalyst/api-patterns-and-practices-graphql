"""Ch17 Transport security and introspection control - the root fields and the schema.

``Query`` has six root fields: ``cargo``, ``cargos``, ``location``, ``voyage``,
``node`` and ``nodes``; ``Mutation`` has one, ``registerHandlingEvent``. Each is
``async def`` and reads or writes through the request's ``TrackingContext``. The
types (and the resolvers on them) live in ``app/model.py``, the seed in
``app/data.py``, the paging rules in ``app/pagination.py``.
"""
from __future__ import annotations

import asyncio
from functools import partial
from typing import Annotated

import strawberry
from strawberry import Info
from strawberry.extensions import DisableIntrospection, MaskErrors, MaxTokensLimiter
from strawberry.schema.config import StrawberryConfig

from app import pagination, registration
from app.context import TrackingContext
from app.errors import should_mask
from app.model import (
    SCALAR_MAP,
    Cargo,
    CargoConnection,
    CargoEdge,
    HandlingEvent,
    Location,
    Node,
    PageInfo,
    RegisterHandlingEventInput,
    RegisterHandlingEventPayload,
    RoutingStatus,
    TrackingId,
    UnLocode,
    Voyage,
)

MAX_TOKENS = 5000


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
        return await resolve_node(info.context, id_)

    @strawberry.field(
        description=(
            "Fetch several objects by their global ids, in the order given. "
            "An unknown id yields null at its position."
        )
    )
    async def nodes(
        self,
        info: Info[TrackingContext],
        ids: Annotated[
            list[strawberry.ID],
            strawberry.argument(description="The global ids of the objects to fetch."),
        ],
    ) -> list[Node | None]:
        # gather starts every load before the event loop turns, so each loader
        # sees all of its keys at once: one bulk call per type. gather also
        # keeps the order of its arguments.
        return list(await asyncio.gather(*(load_node(info.context, id_) for id_ in ids)))

    @strawberry.field(description="List cargos, newest first, as a Relay connection.")
    async def cargos(
        self,
        info: Info[TrackingContext],
        first: Annotated[
            strawberry.Maybe[int | None], strawberry.argument(description="Return the first N cargos.")
        ] = None,
        after: Annotated[
            strawberry.Maybe[str | None], strawberry.argument(description="Return cargos after this cursor.")
        ] = None,
        last: Annotated[
            strawberry.Maybe[int | None], strawberry.argument(description="Return the last N cargos.")
        ] = None,
        before: Annotated[
            strawberry.Maybe[str | None], strawberry.argument(description="Return cargos before this cursor.")
        ] = None,
        routing_status: Annotated[
            strawberry.Maybe[RoutingStatus | None],
            strawberry.argument(
                name="routingStatus", description="Only cargos with this routing status."
            ),
        ] = None,
    ) -> CargoConnection:
        page = pagination.parse_page(
            pagination.argument(first),
            pagination.argument(after),
            pagination.argument(last),
            pagination.argument(before),
            pagination.decode_cargo,
        )
        cargos = await info.context.booking.list_cargos(pagination.argument(routing_status), page)
        edges = [
            CargoEdge(cursor=pagination.encode_cargo(row.key), tracking_id=row.tracking_id)
            for row in cargos.items
        ]
        return CargoConnection(
            edges=edges,
            page_info=PageInfo.of(cargos.has_next, cargos.has_previous, [e.cursor for e in edges]),
            total_count=cargos.total_count,
        )


def _split_id(id_: str) -> tuple[str, str] | None:
    """A global id as (prefix, key); ``None`` for a bare prefix or an empty key."""
    kind, sep, key = id_.partition("_")
    return (kind, key) if sep and key else None


async def resolve_node(context: TrackingContext, id_: str) -> Node | None:
    """One global id to its object, dispatching on the type prefix: one source
    call. Unknown ids give None."""
    parts = _split_id(id_)
    if parts is None:
        return None
    kind, key = parts
    match kind:
        case "cargo":
            return await context.booking.get_cargo(key)
        case "loc":
            return await context.location.get_location(key)
        case "voy":
            return await context.voyage.get_voyage(key)
        case "evt":
            record = await context.handling.get_event(id_)
            return HandlingEvent.of(record) if record else None
        case _:
            return None


async def load_node(context: TrackingContext, id_: str) -> Node | None:
    """Like ``resolve_node``, through the request's loaders: ids of one type
    asked for in the same turn share one bulk call. Events have no bulk read."""
    parts = _split_id(id_)
    if parts is None:
        return None
    kind, key = parts
    match kind:
        case "cargo":
            return await context.loaders.cargo.load(key)
        case "loc":
            return await context.loaders.location.load(key)
        case "voy":
            return await context.loaders.voyage.load(key)
        case _:
            return await resolve_node(context, id_)


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


def schema_for(public: bool) -> strawberry.Schema:
    """Build the schema for a public (hardened) or an internal instance.

    Every extension is passed as a factory (``functools.partial``) or a class, so
    each request gets its own instance. ``MaskErrors`` is an allowlist (see
    app/errors.py). ``MaxTokensLimiter`` makes graphql-core stop parsing a document
    past 5000 tokens. On a public instance ``DisableIntrospection`` rejects
    ``__schema`` and ``__type`` at validation, and ``disable_field_suggestions``
    drops the "Did you mean ..." hint that would otherwise name a real field.
    """
    extensions: list = [
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error."),
        partial(MaxTokensLimiter, max_token_count=MAX_TOKENS),
    ]
    if public:
        extensions.append(DisableIntrospection)
    return strawberry.Schema(
        query=Query,
        mutation=Mutation,
        config=StrawberryConfig(scalar_map=SCALAR_MAP, disable_field_suggestions=public),
        extensions=extensions,
    )
