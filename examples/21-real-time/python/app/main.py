"""Ch21 Real-time - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI
(container port 8080, mapped to host 8311 by ../compose.yaml), plus a
liveness probe at /health and the plain SSE feed at /events/cargos/{trackingId}
(``app/events.py``). ``GraphQLRouter`` gets a ``context_getter`` so each request
carries its own request id and sources (see ``app/deps.py``), and serves
``Subscription.cargoHandled`` over WebSocket and over SSE on the same path.
``/debug/source-calls`` and ``/debug/subscribers`` are mounted only when
``TRACKING_DEBUG_ENDPOINTS=true``.

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
from strawberry.subscriptions import (
    GRAPHQL_SSE_PROTOCOL,
    GRAPHQL_TRANSPORT_WS_PROTOCOL,
    GRAPHQL_WS_PROTOCOL,
)

from app import debug, events
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


app = FastAPI(title="ch21-real-time-python", lifespan=lifespan)
# One path, four ways in: POST for queries and mutations, and the three
# subscription transports named here (graphql-transport-ws and the older
# graphql-ws over WebSocket, graphql-sse over a POST with Accept: text/event-stream).
app.include_router(
    GraphQLRouter(
        schema,
        context_getter=get_context,
        subscription_protocols=(
            GRAPHQL_TRANSPORT_WS_PROTOCOL,
            GRAPHQL_WS_PROTOCOL,
            GRAPHQL_SSE_PROTOCOL,
        ),
    ),
    prefix="/graphql",
)
app.include_router(events.router)
if settings.debug_endpoints:
    app.include_router(debug.router)
    app.include_router(debug.subscribers_router)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "UP"}
