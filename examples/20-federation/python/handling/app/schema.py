"""Ch20 Federation, handling subgraph - the mutation and the schema.

The handling subgraph has one root field, ``Mutation.registerHandlingEvent``,
and no root query fields of its own: the gateway reaches its ``Cargo``
fields through ``Query._entities``. The schema is a
``strawberry.federation.Schema``: it adds ``Query._service`` (the subgraph's SDL,
which the composer reads) and ``Query._entities``, and it declares the
federation version. The types (and the resolvers on them) live in
``app/model.py``, the seed in ``app/data.py``, the paging rules in
``app/pagination.py``.
"""
from __future__ import annotations

from functools import partial
from typing import Annotated

import strawberry
import strawberry.federation
from strawberry import Info
from strawberry.extensions import MaskErrors
from strawberry.schema.config import StrawberryConfig

from app import registration
from app.context import TrackingContext
from app.errors import should_mask
from app.model import (
    SCALAR_MAP,
    RegisterHandlingEventInput,
    RegisterHandlingEventPayload,
)


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


# Federation 2.7 is the version SmallRye's federation support also declares, so
# both stacks' subgraphs compose together.
# MaskErrors replaces the message of every error should_mask accepts. It is an
# allowlist: see app/errors.py.
schema = strawberry.federation.Schema(
    mutation=Mutation,
    federation_version="2.7",
    config=StrawberryConfig(scalar_map=SCALAR_MAP),
    extensions=[
        partial(MaskErrors, should_mask_error=should_mask, error_message="Internal server error.")
    ],
)
