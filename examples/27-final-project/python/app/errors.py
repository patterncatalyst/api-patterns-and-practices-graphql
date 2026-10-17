"""Ch27 The final project - the errors a client may see, and the rule that hides the rest.

``ExposedError`` is the allowlist: only its subclasses reach a client with their
message, and each carries a stable ``extensions["code"]``. Strawberry's
``MaskErrors`` extension replaces every other execution error with a generic
message. It rebuilds the masked error without ``extensions``, so a masked error
carries no code either.

A resolver that wants a client to read its failure raises an ``ExposedError``
subclass. Raising ``GraphQLError`` directly would be masked, because the
predicate only trusts ``ExposedError``.
"""
from __future__ import annotations

from typing import ClassVar

from graphql import GraphQLError


class ExposedError(Exception):
    """A failure whose message is safe to show a client."""

    code: ClassVar[str]

    def __init__(self, message: str) -> None:
        super().__init__(message)
        # graphql-core copies a dict ``extensions`` from the original error
        # onto the GraphQLError it builds.
        self.extensions = {"code": self.code}


class SourceUnavailable(ExposedError):
    """A source cannot answer (the outage seed: booking GHI345)."""

    code = "SERVICE_UNAVAILABLE"


class BadUserInput(ExposedError):
    """A value that passed input coercion but is not acceptable: a page size
    out of range, or a cursor this connection did not issue."""

    code = "BAD_USER_INPUT"


class Unauthenticated(ExposedError):
    """An anonymous caller reached an operation that needs a signed-in one."""

    code = "UNAUTHENTICATED"


class Forbidden(ExposedError):
    """A signed-in caller without the role the operation or field needs."""

    code = "FORBIDDEN"


def should_mask(error: GraphQLError) -> bool:
    """Mask an error unless a resolver raised an ``ExposedError``.

    An error with no ``original_error`` came from the engine itself (a request
    error: parse, validation, coercion) and keeps its message. An error whose
    ``original_error`` is anything but an ``ExposedError`` is an unexpected resolver failure, or
    a null in a non-null field (a ``TypeError``), and is masked.
    """
    return error.original_error is not None and not isinstance(error.original_error, ExposedError)
