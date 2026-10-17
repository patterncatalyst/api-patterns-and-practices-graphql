"""Ch14 Depth limits and query cost analysis - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` (a lab
tool, off by default); ``TRACKING_MAX_QUERY_COST`` is the cost budget.
"""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    max_query_cost: int = 1000
