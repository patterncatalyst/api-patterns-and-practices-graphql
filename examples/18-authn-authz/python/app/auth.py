"""Ch18 AuthN and AuthZ - validating a bearer token into an ``Identity``.

``Authenticator`` wraps PyJWT's ``PyJWKClient`` (signing keys fetched from the
identity provider's JWKS endpoint and cached) and ``jwt.decode``, which checks
the signature, ``exp``, ``iss`` and ``aud``. Nothing here parses a token by hand.

No ``Authorization`` header means an anonymous caller: ``identity_from`` returns
``None`` and the public fields still work. A bearer token that does not
validate never reaches GraphQL: it is HTTP 401 with ``WWW-Authenticate: Bearer``
(RFC 6750, "The WWW-Authenticate Response Header Field").

The ``Identity`` is all the request context keeps of the token. The token
itself is dropped once it is validated.
"""
from __future__ import annotations

from dataclasses import dataclass

import jwt
from fastapi import HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from jwt import PyJWKClient

from app.settings import Settings


@dataclass(frozen=True, slots=True)
class Identity:
    """Who is asking: the token's subject, its realm roles, and the shipper
    organisation it was issued for (None for staff)."""

    subject: str
    roles: frozenset[str]
    shipper: str | None

    @property
    def is_operator(self) -> bool:
        return "operator" in self.roles


class Authenticator:
    def __init__(self, settings: Settings) -> None:
        self._issuer = settings.oidc_issuer
        self._audience = settings.oidc_audience
        # One client for the process: it keeps the fetched key set (default
        # lifespan 300 s) and fetches again when a token names an unknown kid.
        self._jwks = PyJWKClient(settings.oidc_jwks_url, cache_keys=True)

    async def identity_from(self, request: Request) -> Identity | None:
        """The caller's identity, ``None`` for an anonymous caller; HTTP 401
        for a bearer token that does not validate."""
        scheme, _, token = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or not token:
            return None
        try:
            # PyJWKClient does blocking I/O on a cache miss: keep it off the event loop.
            key = await run_in_threadpool(self._jwks.get_signing_key_from_jwt, token)
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
        except jwt.PyJWKClientConnectionError as error:
            raise HTTPException(503, "identity provider unavailable") from error
        except jwt.PyJWTError as error:
            raise HTTPException(
                401, "invalid token", headers={"WWW-Authenticate": 'Bearer error="invalid_token"'}
            ) from error
        return Identity(
            subject=claims["sub"],
            roles=frozenset(claims.get("realm_access", {}).get("roles", [])),
            shipper=claims.get("shipper"),
        )
