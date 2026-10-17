"""Ch16 Caching - ``Cache-Control`` on every GraphQL response.

A response is ``public, max-age=300`` when all of these hold, and ``no-store``
otherwise:

* the request is a GET (RFC 9111 lets a shared cache store only what a cacheable
  method produced, and a POST body is not part of the cache key);
* the result has no errors;
* every root field is reference data: ``location``, ``voyage`` or ``__typename``;
* the request carries no ``Authorization`` header, because what a caller may read
  can depend on who the caller is.

Every ``public`` response also carries ``Vary: Accept``, so a shared cache stores one
entry per ``Accept`` value.

``SchemaExtension.on_operation`` wraps the whole operation, parsing and validation
included. The extension sets ``no-store`` on entry and replaces it with the public
policy after the ``yield`` when the result qualifies. The header goes on the response
FastAPI is about to send (``info.context.response``, Strawberry FastAPI's documented
place for it).
"""
from __future__ import annotations

from collections.abc import Iterator

from graphql.language import FieldNode, OperationDefinitionNode, OperationType
from strawberry.extensions import SchemaExtension

PUBLIC = "public, max-age=300"
NO_STORE = "no-store"
REFERENCE_FIELDS = frozenset({"location", "voyage", "__typename"})


class CachePolicy(SchemaExtension):
    def on_operation(self) -> Iterator[None]:
        context = self.execution_context
        response = context.context.response
        # The default comes first, so a request refused before execution (a hash the server does not
        # know) still carries a policy: the code after this yield runs for operations that complete.
        response.headers["Cache-Control"] = NO_STORE
        yield
        request = context.context.request
        result = context.result
        if (
            request.method == "GET"
            and "authorization" not in request.headers
            and result is not None
            and not result.errors
            and self._only_reference_data()
        ):
            response.headers["Cache-Control"] = PUBLIC
            # The body depends on the Accept header, so a cache keeps one entry per Accept value.
            response.headers["Vary"] = "Accept"

    def _only_reference_data(self) -> bool:
        """True when the selected operation is a query whose root selections are all plain reference fields."""
        context = self.execution_context
        document = context.graphql_document
        if document is None:
            return False
        operations = [
            definition
            for definition in document.definitions
            if isinstance(definition, OperationDefinitionNode)
            and (context.operation_name is None or definition.name and definition.name.value == context.operation_name)
        ]
        return bool(operations) and all(
            operation.operation is OperationType.QUERY
            and all(
                # A fragment spread at the root could hide any field: treat it as not reference data.
                isinstance(selection, FieldNode) and selection.name.value in REFERENCE_FIELDS
                for selection in operation.selection_set.selections
            )
            for operation in operations
        )
