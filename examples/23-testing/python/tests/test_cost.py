"""Resolver layer: the price list, observed through the refusal that states the price.

A schema with a budget one unit under a document's price refuses it before any
resolver runs, so no context is needed and the message names the price.
"""
from functools import partial

import pytest
import strawberry
from strawberry.schema.config import StrawberryConfig

from app.limits import QueryCostLimiter
from app.model import SCALAR_MAP
from app.schema import MAX_TOKENS, Mutation, Query
from support import Documents


pytestmark = pytest.mark.anyio


def schema_with_budget(budget: int) -> strawberry.Schema:
    return strawberry.Schema(
        query=Query,
        mutation=Mutation,
        config=StrawberryConfig(scalar_map=SCALAR_MAP, batching_config=None),
        extensions=[partial(QueryCostLimiter, max_cost=budget, max_tokens=MAX_TOKENS)],
    )


async def test_fan_out_is_priced_at_fifty_three(documents: Documents) -> None:
    result = await schema_with_budget(52).execute(documents.read("fan-out"))

    assert [e.message for e in result.errors] == ["maximum query complexity exceeded 53 > 52"]


async def test_a_page_is_priced_by_the_size_it_asks_for() -> None:
    page = "{ cargos(first: 4) { edges { node { trackingId } } } }"

    result = await schema_with_budget(12).execute(page)

    assert [e.message for e in result.errors] == ["maximum query complexity exceeded 13 > 12"]


async def test_introspection_costs_nothing() -> None:
    result = await schema_with_budget(0).execute("{ __schema { types { name } } }")

    assert result.errors is None
