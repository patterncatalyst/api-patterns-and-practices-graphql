"""Helpers the test modules share."""
from pathlib import Path
from typing import Any

import httpx

DOCUMENTS = Path(__file__).parent / "documents"


class Documents:
    """The client documents shared with the Quarkus suite, graphql-inspector and the load runner."""

    def read(self, name: str) -> str:
        return (DOCUMENTS / f"{name}.graphql").read_text()


async def post(client: httpx.AsyncClient, query: str, variables: dict[str, Any] | None = None) -> dict[str, Any]:
    """POST one operation to ``/graphql`` and return the decoded body.

    A GraphQL response is a JSON body that holds ``data`` beside ``errors``;
    the status line alone says nothing about either, so a caller asserts on the body.
    """
    body: dict[str, Any] = {"query": query}
    if variables:
        body["variables"] = variables
    response = await client.post("/graphql", json=body)
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    return response.json()
