"""Ch24 Debugging - the application's debug category for reference resolution.

``app.resolve`` is a standard-library logger. At DEBUG, each reference resolver
writes one line when its loader returns:
``resolve <Type.field> key=<key> outcome=<found|missing>``. The level is INFO
by default and changes at run time through ``/debug/loggers`` (``app/debug.py``).
The category carries reference keys only: a UN/LOCODE or a voyage number, never
a token, a variable value or an owner.
"""
from __future__ import annotations

import logging

CATEGORY = "app.resolve"

_LOG = logging.getLogger(CATEGORY)


def record(coordinate: str, key: str, value: object | None) -> None:
    """One debug line for a reference the resolver looked up."""
    _LOG.debug("resolve %s key=%s outcome=%s", coordinate, key, "missing" if value is None else "found")
