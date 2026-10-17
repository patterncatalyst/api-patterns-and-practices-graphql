"""Ch5 Schema-first and contract-first - Python side entrypoint.

Serves the Strawberry schema at /graphql through ``GraphQLRouter`` on FastAPI
(container port 8080, mapped to host 8151 by ../compose.yaml), plus a
liveness probe at /health.

Run with the ``opentelemetry-instrument`` wrapper (see ../Containerfile) for
zero-code OTLP tracing when the opt-in ``observability`` compose profile is
up; without a reachable collector the exporter only logs failed exports in
the background and never blocks startup or a request.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI
from strawberry.fastapi import GraphQLRouter

from app.schema import schema

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = FastAPI(title="ch05-contract-python")
app.include_router(GraphQLRouter(schema), prefix="/graphql")


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "UP"}
