"""Ch18 AuthN and AuthZ - settings read from the environment.

``TRACKING_SOURCE_LATENCY_MS`` is how long each source call takes (compose sets
250); ``TRACKING_DEBUG_ENDPOINTS`` turns on ``/debug/source-calls`` (a lab
tool, off by default).

The ``TRACKING_OIDC_*`` values say how a bearer token is validated: the issuer
the token must carry (tokens are fetched at the identity provider's published
address, so ``iss`` is that address), the audience this API answers to, and the
JWKS URL the app reads over the compose network (the back channel).
"""
from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="TRACKING_")

    source_latency_ms: int = 0
    debug_endpoints: bool = False
    oidc_issuer: str = "http://localhost:8282/realms/shipping"
    oidc_audience: str = "tracking-api"
    oidc_jwks_url: str = "http://keycloak:8080/realms/shipping/protocol/openid-connect/certs"
