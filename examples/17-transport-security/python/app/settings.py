"""Ch17 Transport security and introspection control - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` (a lab
tool, off by default); ``TRACKING_PUBLIC`` selects the hardened instance.
"""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    # A public instance is the hardened one: introspection, field suggestions,
    # the IDE and GET queries are off. An internal instance leaves them on.
    public: bool = False
