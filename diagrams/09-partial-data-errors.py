"""Spec for assets/diagrams/09-partial-data-errors.{svg,excalidraw}. Regenerate: python3 -I diagrams/09-partial-data-errors.py

The response is the three-alias query of the chapter (ok, outage, bug) as both stacks
return it; the paths and messages are the values verify.sh asserts. Error order
carries no meaning and is not drawn.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=480, h=350, label="data: three aliases, one response"),
    dict(x=560, y=50, w=480, h=350, label="errors: two entries"),
]
nodes = [
    dict(x=50, y=90, w=420, h=60, style="box", lines=["ok", "cargo ABC123: trackingId resolved"]),
    dict(x=50, y=170, w=420, h=60, style="box", lines=["outage", "cargo JKL567: itinerary.legs[0]"]),
    dict(x=110, y=250, w=360, h=50, style="ghost", lines=["itinerary.legs[0].voyage: null", "the failed field is the hole"]),
    dict(x=50, y=325, w=420, h=56, style="ghost", lines=["bug: null", "delivery is non-null, so the hole is the cargo"]),
    dict(x=590, y=150, w=420, h=90, style="accent", lines=["outage error  code SERVICE_UNAVAILABLE", "voyage service unavailable", 'path ["outage","itinerary","legs",0,"voyage"]']),
    dict(x=590, y=300, w=420, h=80, style="accent", lines=["bug error  code null (Quarkus) / none (Python)", "Internal server error.", 'path ["bug","delivery"]']),
]
edges = [
    dict(x1=590, y1=215, x2=470, y2=275, amber=True, label="path", lx=-6, ly=-8),
    dict(x1=590, y1=340, x2=470, y2=353, amber=True, label="path", ly=-8),
]
notes = [
    dict(x=520, y=28, text="Partial data: the healthy alias survives both failures", anchor="middle", bold=True),
    dict(x=520, y=424, text="A path names where it broke. The null lands at the nearest nullable ancestor.", anchor="middle", size=12, color="#555555"),
]
g.emit("09-partial-data-errors", 1060, 450, bands=bands, nodes=nodes, edges=edges, notes=notes)
