"""Ch24 Debugging - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` and
``/debug/loggers`` (lab tools, off by default); ``TRACKING_PROFILE`` is ``prod``
(the default) or ``dev``: a dev instance serves the GraphiQL page on the GraphQL
path, a production instance does not. Errors are masked the same way in both.
"""
from __future__ import annotations

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    profile: Literal["dev", "prod"] = "prod"
