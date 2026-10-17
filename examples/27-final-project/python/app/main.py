"""Ch27 The final project - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI
(container port 8080, on the backend network of ../compose.yaml; the edge
publishes it as host 8371 over TLS, and the internal instance as 127.0.0.1:8373),
plus the plain SSE feed at /events/cargos/{trackingId} (``app/events.py``).
``GraphQLRouter`` gets a ``context_getter`` so each request carries its own
request id and sources (see ``app/deps.py``), and serves
``Subscription.cargoHandled`` over WebSocket and over SSE on the same path.
``/debug/source-calls`` and ``/debug/subscribers`` are mounted only when
``TRACKING_DEBUG_ENDPOINTS=true``.

Two health routes split what an orchestrator asks. ``/health/live`` answers 200
while the process runs. ``/health/ready`` answers 200 once the lifespan has
built the store and the sources, and 503 before that and during shutdown.

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

from fastapi import FastAPI, Request, Response, status
from strawberry.fastapi import GraphQLRouter
from strawberry.subscriptions import (
    GRAPHQL_SSE_PROTOCOL,
    GRAPHQL_TRANSPORT_WS_PROTOCOL,
    GRAPHQL_WS_PROTOCOL,
)

from app import debug, events
from app.auth import Authenticator
from app.deps import get_context
from app.handling import HandlingStore
from app.schema import schema_for
from app.settings import Settings
from app.sources import SourceCalls

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

settings = Settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.calls = SourceCalls(settings.source_latency_ms)
    app.state.store = HandlingStore()
    app.state.authenticator = Authenticator(settings)
    app.state.ready = True
    yield
    app.state.ready = False


app = FastAPI(title="ch27-final-python", lifespan=lifespan)
app.state.ready = False
# One path, four ways in: POST for queries and mutations, and the three
# subscription transports named here (graphql-transport-ws and the older
# graphql-ws over WebSocket, graphql-sse over a POST with Accept: text/event-stream).
app.include_router(
    GraphQLRouter(
        schema_for(settings.public),
        context_getter=get_context,
        # No IDE on any instance; a public one also takes no GET queries and refuses
        # introspection (Chapter 17).
        graphql_ide=None,
        allow_queries_via_get=not settings.public,
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


@app.get("/health/live", tags=["ops"])
def live() -> dict[str, str]:
    return {"status": "UP"}


@app.get("/health/ready", tags=["ops"])
def ready(request: Request, response: Response) -> dict[str, str]:
    if not request.app.state.ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "DOWN"}
    return {"status": "UP"}
