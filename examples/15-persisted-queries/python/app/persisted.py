"""Ch15 Persisted queries and APQ - Apollo persisted queries and trusted documents.

The example implements Apollo's persisted-query protocol as a Strawberry
``SchemaExtension``. Strawberry's HTTP layer accepts a request with
``query: null`` and passes ``extensions`` on, and ``SchemaExtension.on_operation``
runs before Strawberry looks for the query. ``PersistedQueries`` sits there and
sets ``execution_context.query``.

Two modes, chosen by ``TRACKING_DOCUMENTS_MODE``:

* ``apq``: a client registers a document by sending its text with the SHA-256
  hash; later requests send the hash alone. Anyone can register anything, so
  this is a bandwidth and caching tool, not a security control.
* ``trusted``: only the documents in the manifest
  (``TRACKING_DOCUMENTS_MANIFEST``, an Apollo persisted-query manifest) run.
  Nothing is stored at run time and unknown text is refused.

The store is a ``cachetools.LRUCache`` of at most 1000 documents, so a client
cannot grow it without bound. An evicted hash answers ``PersistedQueryNotFound``
and the client repeats the handshake. ``LRUCache`` is not thread-safe; every
access here runs on the event loop thread, between awaits.
"""
from __future__ import annotations

import hashlib
import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from cachetools import LRUCache
from strawberry.extensions import SchemaExtension

from app.errors import BadUserInput, ExposedError
from app.settings import Settings

STORE_SIZE = 1000


class PersistedQueryNotFound(ExposedError):
    """A hash the server does not know, sent without query text."""

    code = "PERSISTED_QUERY_NOT_FOUND"

    def __init__(self) -> None:
        super().__init__("PersistedQueryNotFound")


class PersistedQueryRequired(ExposedError):
    """Trusted mode: the text is not in the manifest."""

    code = "PERSISTED_QUERY_REQUIRED"

    def __init__(self) -> None:
        super().__init__("only persisted documents are accepted")


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


class PersistedDocuments:
    """The mode, the manifest loaded at start and the bounded run-time store."""

    def __init__(self, *, trusted: bool, manifest_path: str) -> None:
        self.trusted = trusted
        self.manifest: dict[str, str] = {}
        if manifest_path:
            operations = json.loads(Path(manifest_path).read_text())["operations"]
            self.manifest = {op["id"]: op["body"] for op in operations}
        self.store: LRUCache[str, str] = LRUCache(maxsize=STORE_SIZE)

    @classmethod
    def from_settings(cls, settings: Settings) -> PersistedDocuments:
        return cls(trusted=settings.documents_mode == "trusted", manifest_path=settings.documents_manifest)

    def lookup(self, digest: str) -> str | None:
        """The document for a hash: the manifest first, then (apq mode) the store."""
        found = self.manifest.get(digest)
        if found is None and not self.trusted:
            found = self.store.get(digest)
        return found

    def resolve(self, query: str | None, extensions: dict[str, Any] | None) -> str | None:
        """The query text to execute, or an ExposedError that refuses the request."""
        persisted = (extensions or {}).get("persistedQuery")
        digest = persisted.get("sha256Hash") if isinstance(persisted, dict) else None

        if digest is None:
            if self.trusted and query is not None and sha256_hex(query) not in self.manifest:
                raise PersistedQueryRequired
            return query

        if query is None:
            found = self.lookup(digest)
            if found is None:
                raise PersistedQueryNotFound
            return found

        # The server recomputes the hash: a client-supplied one is a claim, not a key.
        if sha256_hex(query) != digest:
            raise BadUserInput("provided sha does not match query")
        if self.trusted:
            if digest not in self.manifest:
                raise PersistedQueryRequired
        else:
            self.store[digest] = query
        return query


class PersistedQueries(SchemaExtension):
    """Resolve ``extensions.persistedQuery`` before Strawberry looks for the query.

    Raising before the ``yield`` ends the operation with a request error and no
    data. The exception is an ``ExposedError``, so its message and code reach
    the client.
    """

    def __init__(self, *, documents: PersistedDocuments) -> None:
        super().__init__()
        self.documents = documents

    def on_operation(self) -> Iterator[None]:
        context = self.execution_context
        context.query = self.documents.resolve(context.query, context.operation_extensions)
        yield


documents = PersistedDocuments.from_settings(Settings())
