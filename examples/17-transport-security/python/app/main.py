"""Ch17 Transport security and introspection control - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI,
over TLS: the Containerfile starts uvicorn with ``--ssl-certfile`` and
``--ssl-keyfile`` on container port 8443 (host 8271 public, 8273 internal; see
../compose.yaml). A liveness probe answers at /health. ``TRACKING_PUBLIC=true`` selects the hardened instance (``schema_for``, no IDE, no GET
queries). ``GraphQLRouter`` gets a ``context_getter`` so each
request carries its own request id and sources (see ``app/deps.py``).
``/debug/source-calls`` is mounted only when ``TRACKING_DEBUG_ENDPOINTS=true``.

Run with the ``opentelemetry-instrument`` wrapper (see ../Containerfile) for
zero-code OTLP tracing when the opt-in ``observability`` compose profile is
up; without a reachable collector the exporter only logs failed exports in
the background and never blocks startup or a request.
"""
from __future__ import annotations

import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from strawberry.fastapi import GraphQLRouter

from app import debug
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
    yield


app = FastAPI(title="ch17-transport-python", lifespan=lifespan)
app.include_router(
    GraphQLRouter(
        schema_for(settings.public),
        context_getter=get_context,
        # No IDE and no GET queries on a public instance. GET stays a read-only
        # path: Strawberry answers a GET mutation with an error either way.
        graphql_ide=None if settings.public else "graphiql",
        allow_queries_via_get=not settings.public,
    ),
    prefix="/graphql",
)
if settings.debug_endpoints:
    app.include_router(debug.router)

# CORS for the one browser origin that may call the API. The preflight answers for
# POST only; any other origin gets no Access-Control-Allow-Origin header.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://tracking.example.com"],
    allow_methods=["POST"],
    allow_headers=["content-type", "authorization"],
)


@app.middleware("http")
async def strict_transport_security(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Tell browsers to use HTTPS only (RFC 6797). Quarkus does the same with
    ``quarkus.http.header."Strict-Transport-Security".value``."""
    response = await call_next(request)
    response.headers["Strict-Transport-Security"] = "max-age=31536000"
    return response


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "UP"}
