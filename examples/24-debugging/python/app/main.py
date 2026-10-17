"""Ch24 Debugging - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI
(container port 8080, mapped to host 8341 by ../compose.yaml; the dev instance
of the same image is host 8343), plus a liveness probe at /health. ``GraphQLRouter`` gets a ``context_getter`` so each
request carries its own request id and sources (see ``app/deps.py``).
``/debug/source-calls`` and ``/debug/loggers`` are mounted only when
``TRACKING_DEBUG_ENDPOINTS=true``. ``TRACKING_PROFILE=dev`` turns the GraphiQL
page on at the GraphQL path (``graphql_ide``); the default, ``prod``, serves none.

Run with the ``opentelemetry-instrument`` wrapper (see ../Containerfile): it
instruments FastAPI and exports traces, metrics and logs over OTLP to the
collector in the ``lgtm`` compose service. The schema's extensions add the
operation span, a span per resolver and the two GraphQL metrics (see
``app/schema.py`` and ``app/telemetry.py``).
"""
from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from strawberry.fastapi import GraphQLRouter

from app import debug
from app.deps import get_context
from app.handling import HandlingStore
from app.schema import schema
from app.settings import Settings
from app.sources import SourceCalls

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

settings = Settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.calls = SourceCalls(settings.source_latency_ms)
    app.state.store = HandlingStore()
    yield


app = FastAPI(title="ch24-debugging-python", lifespan=lifespan)
app.include_router(
    GraphQLRouter(
        schema,
        context_getter=get_context,
        graphql_ide="graphiql" if settings.profile == "dev" else None,
    ),
    prefix="/graphql",
)
if settings.debug_endpoints:
    app.include_router(debug.router)
    app.include_router(debug.loggers)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "UP"}
