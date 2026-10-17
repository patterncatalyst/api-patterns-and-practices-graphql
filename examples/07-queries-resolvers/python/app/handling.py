"""Ch7 Queries and resolvers - what the handling service returns.

A stored handling event is the handling service's record of something that
happened to a cargo. It is not a GraphQL type in this chapter: the event is an
input to ``Cargo.delivery`` (see ``app/derivation.py``), and ``HandlingEvent``
joins the schema with the mutation in Chapter 8.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from app.model import HandlingEventType


@dataclass(frozen=True, slots=True)
class HandlingRecord:
    id: str
    tracking_id: str
    type: HandlingEventType
    un_locode: str
    voyage_number: str | None
    completion_time: datetime
    registration_time: datetime
