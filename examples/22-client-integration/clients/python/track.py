"""Ch22 Client integration - the Python client: gql over httpx.

Usage: python track.py <graphql-url>

The client is built with the canonical SDL as its schema, so gql validates every
document locally before anything is sent. gql.dsl builds a document from that
same schema. Each step prints one JSON line.
"""

import asyncio
import json
import sys
from pathlib import Path

import httpx
from gql import Client, gql
from gql.dsl import DSLQuery, DSLSchema, dsl_gql
from gql.transport.exceptions import TransportQueryError
from gql.transport.httpx import HTTPXAsyncTransport
from graphql import GraphQLError

SCHEMA_DIR = Path("/schema")

TRACK_CARGO = gql(
    """
    query TrackCargo($id: TrackingId!) {
      cargo(trackingId: $id) {
        trackingId
        description
        delivery { transportStatus }
      }
    }
    """
)

# Selects a field the contract does not have.
CARGO_WEIGHT = gql(
    """
    query CargoWeight($id: TrackingId!) {
      cargo(trackingId: $id) { trackingId weight }
    }
    """
)

LIST_CARGOS = gql(
    """
    query ListCargos {
      cargos(first: 10) {
        edges { node { trackingId } }
      }
    }
    """
)


def say(**line: object) -> None:
    print(json.dumps(line), flush=True)


async def main(url: str) -> None:
    sdl = "\n".join(path.read_text() for path in sorted(SCHEMA_DIR.rglob("*.graphql")))

    requests = 0

    async def count_request(request: httpx.Request) -> None:
        nonlocal requests
        requests += 1

    transport = HTTPXAsyncTransport(
        url=url,
        headers={"X-Client-Name": "ch22-python", "X-Client-Version": "1.0.0"},
        event_hooks={"request": [count_request]},
    )
    client = Client(transport=transport, schema=sdl)

    async with client as session:
        data = await session.execute(TRACK_CARGO, variable_values={"id": "ABC123"})
        cargo = data["cargo"]
        say(
            step="track",
            trackingId=cargo["trackingId"],
            description=cargo["description"],
            status=cargo["delivery"]["transportStatus"],
            requests=requests,
        )

        # A document built from the schema's own types.
        ds = DSLSchema(client.schema)
        query = dsl_gql(DSLQuery(ds.Query.location.args(unLocode="NLRTM").select(ds.Location.name)))
        data = await session.execute(query)
        say(step="dsl", location=data["location"]["name"], requests=requests)

        # The schema in hand refuses a document that selects an unknown field,
        # so nothing is sent.
        before = requests
        try:
            await session.execute(CARGO_WEIGHT, variable_values={"id": "ABC123"})
        except GraphQLError as error:
            say(step="local-validation", error=error.message, sent=requests - before)

        # A response with errors raises TransportQueryError, which carries the data
        # and the errors of the response side by side.
        try:
            await session.execute(LIST_CARGOS)
        except TransportQueryError as error:
            edges = error.data["cargos"]["edges"]
            say(
                step="partial",
                edges=len(edges),
                nullNodes=sum(1 for edge in edges if edge["node"] is None),
                errors=len(error.errors),
                codes=sorted({item["extensions"]["code"] for item in error.errors}),
                paths=[item["path"] for item in error.errors],
            )

        say(step="summary", requests=requests)

asyncio.run(main(sys.argv[1]))
