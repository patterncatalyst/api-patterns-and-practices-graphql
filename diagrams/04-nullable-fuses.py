"""Spec for assets/diagrams/04-nullable-fuses.{svg,excalidraw}. Regenerate: python3 -I diagrams/04-nullable-fuses.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=20, w=340, h=520, label="The fuses in the tracking schema"),
    dict(x=380, y=20, w=290, h=520, label="Canonical: CargoEdge.node is Cargo"),
    dict(x=690, y=20, w=290, h=520, label="Strict: CargoEdge.node is Cargo!"),
]
nodes = [
    # Left: the tree, indented one step per level. Accent = a nullable fuse.
    dict(x=40, y=56, w=300, h=52, style="accent", lines=["Query.cargo: Cargo", "fuse: a failed cargo nulls only itself"]),
    dict(x=60, y=122, w=280, h=52, style="accent", lines=["Cargo.itinerary: Itinerary", "fuse: also null until routed"]),
    dict(x=80, y=188, w=260, h=52, style="box", lines=["Itinerary.legs: [Leg!]!", "non-null: passes a null up"]),
    dict(x=100, y=254, w=240, h=52, style="accent", lines=["Leg.voyage: Voyage", "fuse: voyage service may be down"]),
    dict(x=40, y=346, w=300, h=52, style="box", lines=["Query.cargos: CargoConnection!", "non-null: passes a null up"]),
    dict(x=60, y=412, w=280, h=52, style="box", lines=["edges: [CargoEdge!]!", "non-null: passes a null up"]),
    dict(x=80, y=478, w=260, h=52, style="accent", lines=["CargoEdge.node: Cargo", "fuse: one bad item nulls its edge"]),
]
edges = []
# Panels: the same five rows, top to bottom, for a page of three edges where
# edges[1].node fails.
PY = [56, 132, 208, 284, 360]
PH = 48
def panel(x0, rows):
    out = []
    for y, (title, detail, style) in zip(PY, rows):
        out.append(dict(x=x0, y=y, w=250, h=PH, style=style, lines=[title, detail]))
    return out

canonical = [
    ("data", "kept", "box"),
    ("Query.cargos: CargoConnection!", "kept", "box"),
    ("edges: [CargoEdge!]!", "kept: 3 edges", "box"),
    ("edges[1]: CargoEdge!", "kept: { node: null }", "box"),
    ("edges[1].node: Cargo", "nullable: becomes null", "accent"),
]
strict = [
    ("data", "null: no nullable parent left", "accent"),
    ("Query.cargos: CargoConnection!", "null: cannot hold it", "accent"),
    ("edges: [CargoEdge!]!", "null: cannot hold it", "accent"),
    ("edges[1]: CargoEdge!", "null: cannot hold it", "accent"),
    ("edges[1].node: Cargo!", "fails: null plus an error", "accent"),
]
nodes += panel(400, canonical)
nodes += panel(710, strict)
for y_lower, y_upper in zip(PY[1:], PY[:-1]):
    edges.append(dict(x1=835, y1=y_lower, x2=835, y2=y_upper + PH, amber=True))
edges.append(dict(x1=525, y1=PY[4], x2=525, y2=PY[3] + PH, dashed=True, label="stops here", lx=38, ly=4))
nodes.append(dict(x=400, y=448, w=250, h=70, style="box", lines=["2 of 3 cargos delivered", "1 error, data present"]))
nodes.append(dict(x=710, y=448, w=250, h=70, style="box", lines=["0 of 3 cargos delivered", "1 error, data: null"]))
notes = [
    dict(x=525, y=432, text="Blast radius: one edge", anchor="middle", size=12, bold=True),
    dict(x=835, y=432, text="Blast radius: the whole page", anchor="middle", size=12, bold=True),
]
g.emit("04-nullable-fuses", 1000, 560, bands=bands, nodes=nodes, edges=edges, notes=notes)
