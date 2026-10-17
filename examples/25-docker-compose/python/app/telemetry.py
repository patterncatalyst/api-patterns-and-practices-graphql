"""Ch25 Local with Docker Compose - what a span cannot say, as OpenTelemetry metrics.

The traces come from two ready-made pieces: ``opentelemetry-instrument`` wraps
FastAPI (the HTTP server span), and Strawberry's ``OpenTelemetryExtension`` adds
the operation span and one span per resolver. This module adds the two counters
a span does not give, through Strawberry's own seam for code that wraps one
execution, a ``SchemaExtension``:

* ``graphql.errors``, one count per error in the response, by ``error.code``
  (the ``extensions.code`` the error carries, or ``unclassified``) and
  ``graphql.operation.name``;
* ``graphql.field.deprecated.usage``, one count per deprecated field a request
  selects, by ``graphql.field.coordinate`` (``Type.field``), operation name and
  ``client.name`` (the ``X-Client-Name`` request header, or ``unknown``).

``TraceIdExtension`` adds ``extensions.traceId`` to every execution error, the id
a client quotes when it reports a problem.

``drop_arguments`` is the ``arg_filter`` of the OpenTelemetry extension. A
resolver argument is a value, and a value stays out of telemetry; the field
coordinate already says which field ran.
"""
from __future__ import annotations

from collections.abc import Generator
from typing import Any

from graphql import (
    FieldNode,
    GraphQLResolveInfo,
    TypeInfo,
    TypeInfoVisitor,
    Visitor,
    get_operation_ast,
    visit,
)
from opentelemetry import metrics, trace
from strawberry.extensions import SchemaExtension

_METER = metrics.get_meter("com.patterncatalyst.shipping.tracking")
_ERRORS = _METER.create_counter(
    "graphql.errors",
    unit="{error}",
    description="Errors in GraphQL responses, by extensions.code and operation name.",
)
_DEPRECATED_USAGE = _METER.create_counter(
    "graphql.field.deprecated.usage",
    unit="{request}",
    description="Requests that select a deprecated field, by field coordinate, operation name and client.",
)

_CLIENT_HEADER = "x-client-name"


def drop_arguments(args: dict[str, Any], info: GraphQLResolveInfo) -> dict[str, Any]:
    """The ``arg_filter`` of ``OpenTelemetryExtension``: no argument value reaches a span."""
    return {}


class _DeprecatedFields(Visitor):
    """Collects ``Type.field`` for every deprecated field the visited operation selects."""

    def __init__(self, type_info: TypeInfo) -> None:
        super().__init__()
        self._type_info = type_info
        self.coordinates: set[str] = set()

    def enter_field(self, node: FieldNode, *_: Any) -> None:
        field = self._type_info.get_field_def()
        parent = self._type_info.get_parent_type()
        if field is not None and parent is not None and field.deprecation_reason is not None:
            self.coordinates.add(f"{parent.name}.{node.name.value}")  # type: ignore[union-attr]


class OperationMetrics(SchemaExtension):
    """Counts errors by code and deprecated-field usage for each execution."""

    def on_execute(self) -> Generator[None]:
        execution = self.execution_context
        operation = get_operation_ast(execution.graphql_document, execution.operation_name)
        name = operation.name.value if operation is not None and operation.name else "anonymous"
        client = execution.context.request.headers.get(_CLIENT_HEADER) or "unknown"

        if operation is not None:
            # The graphql-core schema behind the Strawberry one; TypeInfo needs it.
            type_info = TypeInfo(execution.schema._schema)
            deprecated = _DeprecatedFields(type_info)
            visit(operation, TypeInfoVisitor(type_info, deprecated))
            for coordinate in deprecated.coordinates:
                _DEPRECATED_USAGE.add(
                    1,
                    {
                        "graphql.field.coordinate": coordinate,
                        "graphql.operation.name": name,
                        "client.name": client,
                    },
                )

        yield

        result = execution.result
        for error in (result.errors or []) if result is not None else []:
            code = (error.extensions or {}).get("code") or "unclassified"
            _ERRORS.add(1, {"error.code": str(code), "graphql.operation.name": name})


class TraceIdExtension(SchemaExtension):
    """Adds ``extensions.traceId`` to every execution error of the response.

    The id is the trace id of the request: the span the FastAPI instrumentation
    opened, joined to the caller's trace when the request carried a
    ``traceparent``. ``on_operation`` is the hook that wraps the whole
    operation, and the schema lists this extension before ``MaskErrors``:
    extensions leave in reverse order, so this exit runs after the masking has
    rebuilt the masked errors, and a masked error ends with ``traceId`` as its
    only extension. The id is not a secret; reading the trace takes access to
    the observability backend. A request error (parse, validation), which has no
    path, is left as the engine wrote it.
    """

    def on_operation(self) -> Generator[None]:
        yield
        errors = getattr(self.execution_context.result, "errors", None)
        context = trace.get_current_span().get_span_context()
        if not errors or not context.is_valid:
            return
        trace_id = trace.format_trace_id(context.trace_id)
        for error in errors:
            if error.path:
                error.extensions = {**(error.extensions or {}), "traceId": trace_id}
