"""Ch18 AuthN and AuthZ - operation and field permissions.

Strawberry's ``BasePermission`` decides; ``on_unauthorized`` chooses the error.
The default error is a ``StrawberryGraphQLError``, which ``MaskErrors`` would
replace with "Internal server error." (``app/errors.py`` trusts only
``ExposedError``), so each class raises an ``ExposedError`` subclass with a
stable code instead.

A field lists the classes in order: ``[IsAuthenticated, IsOperator]`` answers an
anonymous caller with ``UNAUTHENTICATED`` and a signed-in shipper with
``FORBIDDEN``.
"""
from __future__ import annotations

from typing import Any

from strawberry import Info
from strawberry.permission import BasePermission

from app import data
from app.access import visible
from app.context import TrackingContext
from app.errors import Forbidden, Unauthenticated


class IsAuthenticated(BasePermission):
    def has_permission(self, source: Any, info: Info[TrackingContext], **kwargs: Any) -> bool:
        return info.context.identity is not None

    def on_unauthorized(self) -> None:
        raise Unauthenticated("authentication required")


class IsOperator(BasePermission):
    def has_permission(self, source: Any, info: Info[TrackingContext], **kwargs: Any) -> bool:
        identity = info.context.identity
        return identity is not None and identity.is_operator

    def on_unauthorized(self) -> None:
        raise Forbidden("operator role required")


class CanWatchCargo(BasePermission):
    """Chapter 27: the object rule for a subscription. The check runs once, before the
    first event, with the same rule every read of a cargo applies (``app/access.py``): a
    shipper watches its own cargos, an operator any cargo, and a cargo that is not the
    caller's answers like an unknown one."""

    def has_permission(self, source: Any, info: Info[TrackingContext], **kwargs: Any) -> bool:
        return visible(info.context.identity, data.OWNERS.get(kwargs["tracking_id"]))

    def on_unauthorized(self) -> None:
        raise Forbidden("not permitted to watch this cargo")
