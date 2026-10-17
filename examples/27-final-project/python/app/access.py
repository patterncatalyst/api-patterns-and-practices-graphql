"""Ch18 AuthN and AuthZ - the object-level rule, in one place.

A shipper sees the cargos it owns; an operator sees every cargo; an anonymous
caller sees none. ``BookingSource`` applies it to every read: every path to a cargo
(``cargo``, ``cargos``, ``node``, ``nodes``, ``CargoEdge.node``,
``HandlingEvent.cargo``) reads the booking source, so the rule cannot be bypassed
by choosing another path. ``CanWatchCargo`` and the event feed apply the same
function when a subscription or a feed starts (Chapter 27).
"""
from __future__ import annotations

from app.auth import Identity


def visible(identity: Identity | None, owner: str | None) -> bool:
    """Whether the caller may see a cargo owned by ``owner`` (None for an unknown cargo)."""
    if identity is None:
        return False
    return identity.is_operator or (owner is not None and identity.shipper == owner)
