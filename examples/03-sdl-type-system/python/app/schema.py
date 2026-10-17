"""Ch3 SDL and the type system - the root fields and the schema.

``Query`` has four root fields: ``cargo``, ``location``, ``voyage`` and
``node``. They are the only resolvers; every other field is read from the
object it hangs off. The types live in ``app/model.py`` and the seed in
``app/data.py``.
"""
from __future__ import annotations

from typing import Annotated

import strawberry
from strawberry.schema.config import StrawberryConfig

from app import data
from app.model import SCALAR_MAP, Cargo, Location, Node, TrackingId, UnLocode, Voyage


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
        return data.CARGOS.get(tracking_id)

    @strawberry.field(description="Look up a location by UN/LOCODE. Null when unknown.")
    def location(
        self,
        un_locode: Annotated[
            UnLocode,
            strawberry.argument(
                name="unLocode", description="The UN/LOCODE to look up, for example `NLRTM`."
            ),
        ],
    ) -> Location | None:
        return data.LOCATIONS.get(un_locode)

    @strawberry.field(description="Look up a voyage by voyage number. Null when unknown.")
    def voyage(
        self,
        voyage_number: Annotated[
            str,
            strawberry.argument(
                name="voyageNumber", description="The carrier's voyage number, for example `V100S`."
            ),
        ],
    ) -> Voyage | None:
        return data.VOYAGES.get(voyage_number)

    @strawberry.field(
        description="Fetch any object by its global id (Relay Global Object Identification)."
    )
    def node(
        self,
        id_: Annotated[
            strawberry.ID,
            strawberry.argument(name="id", description="The global id of the object to fetch."),
        ],
    ) -> Node | None:
        return data.NODES.get(id_)


schema = strawberry.Schema(query=Query, config=StrawberryConfig(scalar_map=SCALAR_MAP))
