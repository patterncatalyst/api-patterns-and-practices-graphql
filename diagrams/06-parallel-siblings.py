"""Spec for assets/diagrams/06-parallel-siblings.{svg,excalidraw}. Regenerate: python3 -I diagrams/06-parallel-siblings.py

The bars are the source-call log of one real run of the chapter's query on the
Quarkus stack (startMs and endMs, shifted so booking starts at 0). The ghost
lane is the same two calls from blocking resolvers on one event loop
(Strawberry ``def`` resolvers).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X0, SCALE = 190, 0.85  # x of t=0, pixels per millisecond


def bar(label, start, end, y, style="accent"):
    return dict(x=round(X0 + start * SCALE), y=y, w=round((end - start) * SCALE), h=30, style=style, lines=[label])


# (source, label, start, end) from the log; location has two overlapping calls.
bands = [
    dict(x=20, y=50, w=960, h=46, label="booking"),
    dict(x=20, y=104, w=960, h=46, label="routing"),
    dict(x=20, y=158, w=960, h=46, label="delivery"),
    dict(x=20, y=212, w=960, h=84, label="location"),
    dict(x=20, y=330, w=960, h=104, label="sequential", fill="#ffffff"),
]
nodes = [
    bar("getCargo ABC123", 0, 251, 58),
    bar("getItinerary ABC123", 255, 506, 112),
    bar("getDelivery ABC123", 257, 516, 166),
    bar("USNYC", 513, 764, 220),
    bar("DEHAM", 515, 767, 256),
    bar("getItinerary", 0, 250, 366, "ghost"),
    bar("getDelivery", 250, 500, 398, "ghost"),
]
# Time axis ticks: thin boxes with a label below.
# Drawn first so the bars sit on top of them.
for t in (0, 250, 500, 750):
    x = round(X0 + t * SCALE)
    nodes.insert(0, dict(x=x, y=44, w=1, h=392, style="sub", lines=[""]))
notes = [dict(x=round(X0 + t * SCALE), y=454, text=f"{t} ms", anchor="middle", size=11, color="#555555") for t in (0, 250, 500, 750)]
notes += [
    dict(x=500, y=28, text="One query, one request: itinerary and delivery overlap, then the two location calls overlap", anchor="middle", bold=True),
    dict(x=500, y=476, text="Solid bars are 250 ms source calls from the source-call log of one run. Ghost bars: the same two calls from blocking resolvers on one event loop.", anchor="middle", size=12, color="#555555"),
    dict(x=500, y=494, text="The chapter asserts overlap and order, never duration.", anchor="middle", size=12, color="#555555"),
]
g.emit("06-parallel-siblings", 1000, 510, bands=bands, nodes=nodes, notes=notes)
