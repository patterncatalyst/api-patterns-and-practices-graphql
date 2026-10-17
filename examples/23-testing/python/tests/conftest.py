"""Shared fixtures for the Python test suite.

The environment is set before ``app`` is imported: ``app.main`` reads its
settings at import time, and the suite runs with no source latency and the
debug endpoints off. The suite reads the source-call log from
``app.state.calls`` instead.
"""
import os

os.environ["TRACKING_SOURCE_LATENCY_MS"] = "0"
os.environ["TRACKING_DEBUG_ENDPOINTS"] = "false"
os.environ["OTEL_SDK_DISABLED"] = "true"

from collections.abc import AsyncIterator  # noqa: E402

import httpx  # noqa: E402
import pytest  # noqa: E402
from asgi_lifespan import LifespanManager  # noqa: E402

from app.main import app  # noqa: E402
from app.sources import SourceCalls  # noqa: E402
from support import Documents  # noqa: E402


@pytest.fixture
def anyio_backend() -> str:
    """The AnyIO pytest plugin runs ``@pytest.mark.anyio`` tests on this backend."""
    return "asyncio"


# The application in process, lifespan included. ASGITransport does not run the
# lifespan, and the application creates its source-call log and handling store
# there, so LifespanManager starts it. Every test gets a fresh application state.
@pytest.fixture
async def app_client() -> AsyncIterator[httpx.AsyncClient]:
    async with LifespanManager(app) as manager:
        transport = httpx.ASGITransport(app=manager.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


@pytest.fixture
def calls(app_client: httpx.AsyncClient) -> SourceCalls:
    """The source-call log of the application ``app_client`` started."""
    return app.state.calls


@pytest.fixture(scope="session")
def documents() -> Documents:
    return Documents()
