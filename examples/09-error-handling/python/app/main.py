"""Ch9 Error handling - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI
(container port 8080, mapped to host 8191 by ../compose.yaml), plus a
liveness probe at /health. ``GraphQLRouter`` gets a ``context_getter`` so each
request carries its own request id and sources (see ``app/deps.py``).
``/debug/source-calls`` is mounted only when ``TRACKING_DEBUG_ENDPOINTS=true``.

Run with the ``opentelemetry-instrument`` wrapper (see ../Containerfile) for
zero-code OTLP tracing when the opt-in ``observability`` compose profile is
up; without a reachable collector the exporter only logs failed exports in
the background and never blocks startup or a request.
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


app = FastAPI(title="ch09-errors-python", lifespan=lifespan)
app.include_router(GraphQLRouter(schema, context_getter=get_context), prefix="/graphql")
if settings.debug_endpoints:
    app.include_router(debug.router)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "UP"}
