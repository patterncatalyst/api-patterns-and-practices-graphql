"""Spec for assets/diagrams/03-selection-onto-types.{svg,excalidraw}. Regenerate: python3 -I diagrams/03-selection-onto-types.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Five rows, one per step of the walk. Left: the selection, indented one step
# per level. Middle: the type each step lands on. Right: the JSON it produces,
# indented the same way.
ROW_Y = [70, 150, 230, 310, 390]
H = 54
query = ["query { ... }", 'cargo(trackingId: "ABC123")', "itinerary", "legs", "voyage { number }"]
types = [
    ("Query", "root operation type"),
    ("Cargo", "nullable"),
    ("Itinerary", "nullable"),
    ("[Leg!]!", "list of non-null Leg"),
    ("Voyage", "nullable"),
]
response = ['{ "data": {', '"cargo": {', '"itinerary": {', '"legs": [ {', '"voyage": { "number": "V100S" } ...']
fields = ["cargo", "itinerary", "legs", "voyage"]

nodes = []
edges = []
LEFT_X, LEFT_W = 30, 250
MID_X, MID_W = 390, 190
RIGHT_X, RIGHT_W = 670, 290
for i, y in enumerate(ROW_Y):
    nodes.append(dict(x=LEFT_X + i * 12, y=y, w=LEFT_W - i * 12, h=H, style="user", lines=[query[i]]))
    t, d = types[i]
    nodes.append(dict(x=MID_X, y=y, w=MID_W, h=H, style="accent" if i else "box", lines=[t, d]))
    nodes.append(dict(x=RIGHT_X + i * 10, y=y, w=RIGHT_W - i * 10, h=H, style="box", lines=[response[i]]))
    edges.append(dict(x1=LEFT_X + LEFT_W, y1=y + H / 2, x2=MID_X, y2=y + H / 2, amber=True))
    edges.append(dict(x1=MID_X + MID_W, y1=y + H / 2, x2=RIGHT_X + i * 10, y2=y + H / 2, amber=True))
for i, f in enumerate(fields):
    edges.append(dict(x1=MID_X + MID_W / 2, y1=ROW_Y[i] + H, x2=MID_X + MID_W / 2, y2=ROW_Y[i + 1], label=f, lx=48, ly=4))
notes = [
    dict(x=155, y=44, text="Selection (query text)", anchor="middle", bold=True),
    dict(x=485, y=44, text="Type each field lands on", anchor="middle", bold=True),
    dict(x=820, y=44, text="Response (same nesting)", anchor="middle", bold=True),
    dict(x=490, y=480, text="Each field name in the query picks an edge in the type graph; the result is nested in the same shape.", anchor="middle", size=12, color="#555555"),
]
g.emit("03-selection-onto-types", 980, 500, nodes=nodes, edges=edges, notes=notes)
