"""Spec for assets/diagrams/03-node-dispatch.{svg,excalidraw}. Regenerate: python3 -I diagrams/03-node-dispatch.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=30, y=150, w=230, h=120, style="user", lines=["Operation", 'node(id: "loc_NLRTM") {', "__typename", "... on Location { unLocode }", "... on Cargo { trackingId } }"]),
    dict(x=330, y=60, w=190, h=60, style="sub", lines=["Id space", "loc_* Location, cargo_* Cargo", "voy_* Voyage"]),
    dict(x=330, y=165, w=190, h=90, style="box", lines=["Query.node(id)", "looks the id up", "in the seed", "and returns the object"]),
    dict(x=590, y=165, w=170, h=90, style="accent", lines=["Runtime type", "Location", "(implements Node)"]),
    dict(x=590, y=300, w=170, h=64, style="accent", lines=["... on Location", "applies: add unLocode"]),
    dict(x=590, y=395, w=170, h=64, style="ghost", lines=["... on Cargo", "skipped: not a Cargo"]),
    dict(x=330, y=345, w=190, h=84, style="box", lines=["Response object", '{"__typename": "Location",', '"unLocode": "NLRTM"}']),
]
edges = [
    dict(x1=260, y1=210, x2=330, y2=210, label="id: ID!", ly=-8),
    dict(x1=425, y1=120, x2=425, y2=165, label="lookup", lx=30, ly=-2),
    dict(x1=520, y1=210, x2=590, y2=210, amber=True, label="object", ly=-8),
    dict(x1=675, y1=255, x2=675, y2=300, amber=True, label="runtime type", lx=48, ly=-2),
    dict(x1=590, y1=332, x2=520, y2=372, amber=True, label="adds unLocode", lx=-30, ly=-14),
    dict(x1=590, y1=427, x2=520, y2=405, dashed=True, label="adds nothing", lx=-8, ly=22),
]
notes = [
    dict(x=400, y=28, text="The id picks the object; the object's type picks the fragments", anchor="middle", bold=True),
]
g.emit("03-node-dispatch", 800, 480, nodes=nodes, edges=edges, notes=notes)
