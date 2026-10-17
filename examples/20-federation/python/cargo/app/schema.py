"""Ch20 Federation, cargo subgraph - the root fields and the schema.

``Query`` has four root fields: ``cargo``, ``cargos``, ``location`` and
``voyage``. The schema is a ``strawberry.federation.Schema``: it adds
``Query._service`` (the subgraph's SDL, which the composer reads) and
``Query._entities`` (which a gateway calls with representations of ``Cargo``,
``Location`` and ``Voyage``), and it declares the federation version. Each
resolver is ``async def`` and reads through the request's ``TrackingContext``.
The types (and the resolvers on them) live in ``app/model.py``, the seed in
``app/data.py``, the paging rules in ``app/pagination.py``.
"""
from __future__ import annotations

from functools import partial
from typing import Annotated

import strawberry
import strawberry.federation
from strawberry import Info
from strawberry.extensions import MaskErrors
from strawberry.schema.config import StrawberryConfig

from app import pagination
from app.context import TrackingContext
from app.errors import should_mask
from app.model import (
    SCALAR_MAP,
    Cargo,
    CargoConnection,
    CargoEdge,
    Location,
    PageInfo,
    RoutingStatus,
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


# Federation 2.7 is the version SmallRye's federation support also declares, so
# both stacks' subgraphs compose together.
# MaskErrors replaces the message of every error should_mask accepts. It is an
# allowlist: see app/errors.py.
schema = strawberry.federation.Schema(
    query=Query,
    federation_version="2.7",
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error.")
    ],
)
