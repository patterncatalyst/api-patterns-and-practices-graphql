"""Spec for assets/diagrams/10-demand-oriented-schema.{svg,excalidraw}. Regenerate: python3 -I diagrams/10-demand-oriented-schema.py

Data movement: the tracking screen's three panels select fields, and each field is
owned by one or more sources.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=20, y=50, w=200, h=70, style="user", lines=["Status header", "state, ETA, next step"]),
    dict(x=20, y=200, w=200, h=70, style="user", lines=["Route", "legs, ports, vessels"]),
    dict(x=20, y=320, w=200, h=70, style="user", lines=["Timeline", "handling events"]),
    dict(x=330, y=15, w=250, h=70, style="accent", lines=["cargo(trackingId)", "trackingId, description"]),
    dict(x=330, y=105, w=250, h=70, style="accent", lines=["cargo.delivery", "transportStatus, ETA,", "nextExpectedActivity"]),
    dict(x=330, y=200, w=250, h=70, style="accent", lines=["cargo.itinerary.legs", "loadLocation, voyage,", "unloadLocation"]),
    dict(x=330, y=320, w=250, h=70, style="accent", lines=["cargo.handlingHistory", "type, location,", "completionTime"]),
    dict(x=700, y=20, w=200, h=50, style="box", lines=["booking"]),
    dict(x=700, y=100, w=200, h=50, style="box", lines=["routing"]),
    dict(x=700, y=180, w=200, h=50, style="box", lines=["voyage"]),
    dict(x=700, y=260, w=200, h=50, style="box", lines=["location"]),
    dict(x=700, y=340, w=200, h=50, style="box", lines=["handling"]),
]
edges = [
    dict(x1=220, y1=75, x2=330, y2=50, label="selects", lx=0, ly=-10),
    dict(x1=220, y1=100, x2=330, y2=135, amber=True, label="selects", lx=0, ly=22),
    dict(x1=220, y1=235, x2=330, y2=235, amber=True, label="selects", ly=-10),
    dict(x1=220, y1=355, x2=330, y2=355, amber=True, label="selects", ly=-10),
    dict(x1=580, y1=50, x2=700, y2=45, label="reads", ly=-10),
    dict(x1=580, y1=130, x2=700, y2=125, label="reads", ly=-10),
    dict(x1=580, y1=235, x2=700, y2=205, label="reads", lx=-10, ly=-30),
    dict(x1=580, y1=250, x2=700, y2=285, label="reads", lx=0, ly=22),
    dict(x1=580, y1=355, x2=700, y2=365, label="reads", ly=-10),
    dict(x1=580, y1=215, x2=700, y2=115),
    dict(x1=580, y1=340, x2=700, y2=300),
    dict(x1=580, y1=155, x2=700, y2=355, dashed=True),
]
notes = [
    dict(x=470, y=420, text="One screen, one query, five owners. The client names the fields; the graph decides which source answers.", anchor="middle", size=12, color="#555555"),
    dict(x=470, y=438, text="Money and booking writes stay out of the graph: no screen reads them.", anchor="middle", size=12, color="#555555"),
]
g.emit("10-demand-oriented-schema", 940, 455, nodes=nodes, edges=edges, notes=notes)
