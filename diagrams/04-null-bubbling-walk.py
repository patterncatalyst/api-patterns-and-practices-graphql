"""Spec for assets/diagrams/04-null-bubbling-walk.{svg,excalidraw}. Regenerate: python3 -I diagrams/04-null-bubbling-walk.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Five rows of the MNO901 response tree, top to bottom. Left: the type position.
# Middle: the value in the response once the step has run. The null enters at
# the bottom row and climbs until a nullable position can hold it; no arrow
# leaves Cargo.itinerary, because the climb stops there.
ROW_Y = [66, 146, 226, 306, 386]
H = 56
LEFT_X, LEFT_W = 30, 310
VAL_X, VAL_W = 410, 230
positions = [
    ("Query.cargo: Cargo", "nullable, never reached by the null", "box"),
    ("4  Cargo.itinerary: Itinerary", "nullable: it can hold the null", "accent"),
    ("3  Itinerary.legs: [Leg!]!", "non-null: cannot hold a null", "box"),
    ("2  legs[0]: Leg!", "non-null: cannot hold a null", "box"),
    ("1  Leg.loadLocation: Location!", "source returned null for XXBAD", "accent"),
]
values = [
    ('cargo: { trackingId: "MNO901", ... }', "box"),
    ("itinerary: null", "accent"),
    ("legs: null", "box"),
    ("legs[0]: null", "box"),
    ("loadLocation: null", "accent"),
]
nodes = []
edges = []
for i, y in enumerate(ROW_Y):
    title, detail, style = positions[i]
    nodes.append(dict(x=LEFT_X, y=y, w=LEFT_W, h=H, style=style, lines=[title, detail]))
    text, vstyle = values[i]
    nodes.append(dict(x=VAL_X, y=y, w=VAL_W, h=H, style=vstyle, lines=["Value in data", text]))
    edges.append(dict(x1=LEFT_X + LEFT_W, y1=y + H / 2, x2=VAL_X, y2=y + H / 2))
for i in range(4, 1, -1):  # three climbs: the null stops at Cargo.itinerary
    edges.append(dict(x1=185, y1=ROW_Y[i], x2=185, y2=ROW_Y[i - 1] + H, amber=True,
                      label="null moves up" if i == 4 else "", lx=62, ly=4))
nodes.append(dict(x=740, y=386, w=230, h=70, style="accent", lines=["errors[0].path", '["cargo", "itinerary",', '"legs", 0, "loadLocation"]']))
edges.append(dict(x1=740, y1=421, x2=VAL_X + VAL_W, y2=421, amber=True, label="points to step 1", lx=0, ly=-10))
nodes.append(dict(x=30, y=478, w=940, h=58, style="user",
                  lines=["Response", '{"data":{"cargo":{"trackingId":"MNO901","itinerary":null}},"errors":[{"path":[...,"loadLocation"]}]}']))
notes = [
    dict(x=185, y=44, text="Type position", anchor="middle", bold=True),
    dict(x=525, y=44, text="Value after the step", anchor="middle", bold=True),
    dict(x=855, y=44, text="Error", anchor="middle", bold=True),
    dict(x=855, y=250, text="The error records where the failure", anchor="middle", size=12, color="#555555"),
    dict(x=855, y=268, text="happened, not where the null landed.", anchor="middle", size=12, color="#555555"),
]
g.emit("04-null-bubbling-walk", 1000, 556, nodes=nodes, edges=edges, notes=notes)
