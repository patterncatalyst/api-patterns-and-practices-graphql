"""Spec for assets/diagrams/22-client-landscape.{svg,excalidraw}. Regenerate: python3 -I diagrams/22-client-landscape.py

The three clients of examples/22-client-integration side by side: how a document
is written, how results are typed, where the schema is checked, what is cached, how
a partial result is read, and the subscription route (Chapter 21).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

cols = [
    ("SmallRye typesafe and dynamic (Java)", 30, [
        ("Document", "annotated interface; return type = selection"),
        ("Typing", "records and enums"),
        ("Schema check", "the server validates"),
        ("Cache", "none built in"),
        ("Partial result", "ErrorOr<T> on the field that may fail"),
        ("Subscriptions", "Multi<T> methods"),
    ]),
    ("gql (Python)", 350, [
        ("Document", "gql(\"...\") text, or gql.dsl built from the schema"),
        ("Typing", "dicts; ariadne-codegen adds models"),
        ("Schema check", "local, against the SDL given to Client"),
        ("Cache", "none built in"),
        ("Partial result", "TransportQueryError carries data and errors"),
        ("Subscriptions", "session.subscribe over WebSocket"),
    ]),
    ("Apollo Client (TypeScript)", 670, [
        ("Document", ".graphql files compiled by codegen"),
        ("Typing", "TypedDocumentNode from the client preset"),
        ("Schema check", "at build time, by codegen"),
        ("Cache", "normalized InMemoryCache"),
        ("Partial result", "errors beside data (errorPolicy)"),
        ("Subscriptions", "GraphQLWsLink over graphql-ws"),
    ]),
]
bands, nodes, notes = [], [], []
row_y = [90 + i * 62 for i in range(6)]
for title, x, rows in cols:
    bands.append(dict(x=x - 10, y=50, w=300, h=432, label=title))
    for (name, detail), y in zip(rows, row_y):
        nodes.append(dict(x=x, y=y + 10, w=280, h=52, style="accent" if name in ("Schema check", "Cache") else "box", lines=[name, detail]))
notes.append(dict(x=500, y=28, text="Three clients, one contract: what each one adds over curl", anchor="middle", bold=True))
notes.append(dict(x=20, y=506, text="All three send the same documents to both servers; verify.sh runs each against Quarkus and Python.", size=12, color="#555555"))
g.emit("22-client-landscape", 1000, 520, bands=bands, nodes=nodes, edges=[], notes=notes)
