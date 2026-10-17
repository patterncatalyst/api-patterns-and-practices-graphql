"""Ch27 The final project - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` (a lab tool,
off by default); ``TRACKING_MAX_QUERY_COST`` is the cost budget;
``TRACKING_PUBLIC`` selects the hardened instance.

The ``TRACKING_OIDC_*`` values say how a bearer token is validated: the issuer
the token must carry (tokens are fetched at the identity provider's published
address, so ``iss`` is that address), the audience this API answers to, and the
JWKS URL the app reads over the backend network (the back channel).
"""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    max_query_cost: int = 1000
    # A public instance is the hardened one: introspection and field suggestions are off
    # (Chapter 17). An internal instance of the same image leaves them on.
    public: bool = False
    oidc_issuer: str = "http://localhost:8374/realms/shipping"
    oidc_audience: str = "tracking-api"
    oidc_jwks_url: str = "http://keycloak:8080/realms/shipping/protocol/openid-connect/certs"
