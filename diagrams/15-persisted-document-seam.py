"""Spec for assets/diagrams/15-persisted-document-seam.{svg,excalidraw}. Regenerate: python3 -I diagrams/15-persisted-document-seam.py

The path of round trip 3 of examples/15-persisted-queries (a hash alone, text
in the store) through each stack, from the code the example runs: on Quarkus
PersistedDocumentRoute, a Vert.x route at order -10, then SmallRye GraphQL; on
Python the PersistedQueries extension's on_operation, then Strawberry's parse
and validate steps with ParserCache and ValidationCache.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=520, h=520, label="Quarkus: a route in front of SmallRye GraphQL"),
    dict(x=560, y=50, w=520, h=520, label="Python: an extension inside Strawberry"),
]
nodes = [
    dict(x=60, y=90, w=440, h=62, style="accent", lines=["Vert.x route /graphql, order -10", "reads extensions.persistedQuery.sha256Hash"]),
    dict(x=60, y=185, w=440, h=62, style="accent", lines=["resolve the hash", "manifest first, then the quarkus-cache store"]),
    dict(x=60, y=280, w=440, h=62, style="accent", lines=["rc.reroute(..., /graphql?query=text&variables=...)", "on GET the operation type is checked first"]),
    dict(x=60, y=375, w=440, h=62, style="box", lines=["SmallRye route: query is now present", "the extensions were read before this route"]),
    dict(x=60, y=470, w=440, h=62, style="box", lines=["parse and validate, document cached by text", "then execute"]),
    dict(x=600, y=90, w=440, h=62, style="box", lines=["GraphQLRouter HTTP view", "accepts query: null and passes extensions on"]),
    dict(x=600, y=185, w=440, h=62, style="accent", lines=["PersistedQueries.on_operation", "sets execution_context.query from the hash"]),
    dict(x=600, y=280, w=440, h=62, style="box", lines=["Strawberry looks for the query", "it is set, so MissingQueryError is not raised"]),
    dict(x=600, y=375, w=440, h=62, style="box", lines=["ParserCache and ValidationCache", "reuse the parse and validation of text seen before"]),
    dict(x=600, y=470, w=440, h=62, style="box", lines=["execute", "the operation type is checked against GET here"]),
]
edges = [dict(x1=280, y1=152, x2=280, y2=185), dict(x1=280, y1=247, x2=280, y2=280, amber=True),
         dict(x1=280, y1=342, x2=280, y2=375), dict(x1=280, y1=437, x2=280, y2=470),
         dict(x1=820, y1=152, x2=820, y2=185), dict(x1=820, y1=247, x2=820, y2=280, amber=True),
         dict(x1=820, y1=342, x2=820, y2=375), dict(x1=820, y1=437, x2=820, y2=470)]
notes = [
    dict(x=550, y=28, text="Where a persisted document is resolved: a route on Quarkus, an extension on Python", anchor="middle", bold=True),
    dict(x=550, y=594, text="The highlighted steps are the example's implementation of Apollo's protocol.", anchor="middle", size=12, color="#555555"),
]
g.emit("15-persisted-document-seam", 1100, 620, bands=bands, nodes=nodes, edges=edges, notes=notes)
