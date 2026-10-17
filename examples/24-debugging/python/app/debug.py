"""Ch24 Debugging - the lab endpoints over HTTP: the source-call log and the log levels.

Included in the application only when ``TRACKING_DEBUG_ENDPOINTS=true``. Plain
FastAPI routers beside ``/graphql``, so they add nothing to the GraphQL schema.
The responses use camelCase keys (``startMs``, ``endMs``, ``effectiveLevel``) so
both stacks serve the same JSON.

``/debug/loggers`` changes the level of one logger at run time, over the
standard library's ``logging`` module (``Logger.setLevel``). It takes the same
form fields as the logging manager of the Quarkus side, ``loggerName`` and
``loggerLevel``, and answers ``201`` as it does.
"""
from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Form, HTTPException, Query, Response, status
from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

from app.deps import get_calls
from app.sources import SourceCalls

router = APIRouter(prefix="/debug/source-calls", tags=["debug"])
loggers = APIRouter(prefix="/debug/loggers", tags=["debug"])


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


class LoggerLevel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, validate_by_name=True)

    name: str
    effective_level: str
    configured_level: str | None = None


def _level_of(name: str) -> LoggerLevel:
    logger = logging.getLogger(name)
    return LoggerLevel(
        name=name,
        effective_level=logging.getLevelName(logger.getEffectiveLevel()),
        configured_level=logging.getLevelName(logger.level) if logger.level else None,
    )


@loggers.get("", response_model_by_alias=True, response_model_exclude_none=True)
def read_level(logger_name: Annotated[str, Query(alias="loggerName")]) -> LoggerLevel:
    return _level_of(logger_name)


@loggers.post("", status_code=status.HTTP_201_CREATED)
def set_level(
    logger_name: Annotated[str, Form(alias="loggerName")],
    logger_level: Annotated[str, Form(alias="loggerLevel")],
) -> Response:
    level = logging.getLevelNamesMapping().get(logger_level.upper())
    if level is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, f"unknown level {logger_level}")
    logging.getLogger(logger_name).setLevel(level)
    return Response(status_code=status.HTTP_201_CREATED)
