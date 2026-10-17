"""Ch16 Caching - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` (a lab
tool, off by default). ``TRACKING_DOCUMENTS_MODE`` is ``apq`` (clients register
documents at run time) or ``trusted`` (only the manifest at
``TRACKING_DOCUMENTS_MANIFEST`` runs; this chapter runs ``apq`` only).
``TRACKING_HANDLING_CACHE_TTL_SECONDS`` is how long a cargo's handling events
stay cached (compose sets 5 so the lab can watch an entry expire).
"""
from __future__ import annotations

from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    documents_mode: Literal["apq", "trusted"] = "apq"
    documents_manifest: str = ""
    handling_cache_ttl_seconds: int = 60
