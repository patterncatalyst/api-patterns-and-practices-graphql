"""Spec for assets/diagrams/22-codegen-loop.{svg,excalidraw}. Regenerate: python3 -I diagrams/22-codegen-loop.py

The client build of examples/22-client-integration/clients/js. The canonical SDL
arrives as the `schema` build context; codegen emits TypedDocumentNodes for the
three operations; tsc checks main.ts against them; the codegen-check fixture
(a document selecting Cargo.weight) stops codegen with exit 1 and writes nothing
(verify.sh asserts the message).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=250, label="Image build: types come from the contract"),
    dict(x=20, y=320, w=960, h=170, label="codegen-check: a document the contract does not support"),
]
nodes = [
    dict(x=40, y=90, w=200, h=70, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "build context: schema"]),
    dict(x=40, y=190, w=200, h=70, style="box", lines=["src/operations.graphql", "TrackCargo, TrackCargoBrief,", "RegisterHandling, ListCargos"]),
    dict(x=290, y=135, w=190, h=80, style="box", lines=["graphql-codegen", "client preset 6.2.3", "npm run codegen"]),
    dict(x=530, y=135, w=200, h=80, style="box", lines=["src/gql/graphql.ts", "TrackCargoDocument ...", "typed documents and results"]),
    dict(x=780, y=90, w=180, h=70, style="box", lines=["tsc --noEmit", "TypeScript 7.0.2", "checks src/main.ts"]),
    dict(x=780, y=190, w=180, h=70, style="ink", lines=["node src/main.ts", "type stripping, Node 24", "runs the client"]),
    dict(x=40, y=360, w=230, h=90, style="box", lines=["fixtures/cargo-weight.graphql", "cargo(trackingId: $id) {", "trackingId weight }"]),
    dict(x=320, y=370, w=190, h=70, style="box", lines=["graphql-codegen", "npm run codegen:check"]),
    dict(x=560, y=360, w=400, h=90, style="accent", lines=["exit 1, no files generated", 'Cannot query field "weight" on type "Cargo"', "at fixtures/cargo-weight.graphql:4:5"]),
]
edges = [
    dict(x1=240, y1=125, x2=290, y2=165, label="schema", lx=-6, ly=-6),
    dict(x1=240, y1=225, x2=290, y2=190, label="documents", lx=-8, ly=18),
    dict(x1=480, y1=175, x2=530, y2=175, amber=True),
    dict(x1=730, y1=160, x2=780, y2=125, label="types", lx=4, ly=-8),
    dict(x1=870, y1=160, x2=870, y2=190, amber=True),
    dict(x1=270, y1=405, x2=320, y2=405),
    dict(x1=510, y1=405, x2=560, y2=405, amber=True, label="refused", lx=0, ly=-14),
]
notes = [
    dict(x=500, y=28, text="One contract, two readers: the generated types and the refusal both come from contracts/schema/", anchor="middle", bold=True),
    dict(x=40, y=478, text="Both stages run the same codegen against the same schema; a document that selects a field the contract lacks never becomes a type.", size=12, color="#555555"),
]
g.emit("22-codegen-loop", 1000, 500, bands=bands, nodes=nodes, edges=edges, notes=notes)
