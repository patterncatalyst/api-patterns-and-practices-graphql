"""Ch14 Depth limits and query cost analysis - the source-call log over HTTP (lab only).

Included in the application only when ``TRACKING_DEBUG_ENDPOINTS=true``. A
plain FastAPI router beside ``/graphql``, so it adds nothing to the GraphQL
schema. The response uses camelCase keys (``startMs``, ``endMs``) so both
stacks serve the same JSON.
"""
from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

from app.deps import get_calls
from app.sources import SourceCalls

router = APIRouter(prefix="/debug/source-calls", tags=["debug"])


class SourceCallOut(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, validate_by_name=True, from_attributes=True)

    request: str
    source: str
    op: str
    key: str
    start_ms: int
    end_ms: int


class CallLog(BaseModel):
    calls: list[SourceCallOut]


@router.get("")
def list_calls(calls: Annotated[SourceCalls, Depends(get_calls)]) -> CallLog:
    return CallLog(calls=[SourceCallOut.model_validate(c) for c in calls.snapshot()])


@router.delete("", status_code=status.HTTP_204_NO_CONTENT)
def reset_calls(calls: Annotated[SourceCalls, Depends(get_calls)]) -> Response:
    calls.reset()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
