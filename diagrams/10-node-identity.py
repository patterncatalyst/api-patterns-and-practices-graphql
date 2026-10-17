"""Spec for assets/diagrams/10-node-identity.{svg,excalidraw}. Regenerate: python3 -I diagrams/10-node-identity.py

Data movement: ids reach a client cache along three paths, and node(id:) or
nodes(ids:) turns any of them back into the same object through the prefix dispatch.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=20, y=40, w=230, h=60, style="user", lines=["cargo { id }", "cargo_ABC123"]),
    dict(x=20, y=140, w=230, h=60, style="user", lines=["leg.loadLocation { id }", "loc_USNYC"]),
    dict(x=20, y=240, w=230, h=60, style="user", lines=["handling event { id }", "evt_1"]),
    dict(x=350, y=100, w=230, h=140, style="accent", lines=["Client cache", "keyed by id", "cargo_ABC123", "loc_USNYC", "evt_1"]),
    dict(x=680, y=40, w=250, h=60, style="box", lines=["node(id:) / nodes(ids:)", "one id, or a list of ids"]),
    dict(x=680, y=140, w=250, h=70, style="box", lines=["Prefix dispatch", "cargo_  loc_  voy_  evt_"]),
    dict(x=680, y=250, w=250, h=60, style="sub", lines=["Owning source", "booking, location, voyage, handling"]),
]
edges = [
    dict(x1=250, y1=70, x2=350, y2=140, label="id", lx=-4, ly=-12),
    dict(x1=250, y1=170, x2=350, y2=170, label="id", ly=-10),
    dict(x1=250, y1=270, x2=350, y2=200, label="id", lx=-4, ly=24),
    dict(x1=580, y1=130, x2=680, y2=70, amber=True, label="refetch by id", lx=-10, ly=-22),
    dict(x1=805, y1=100, x2=805, y2=140, label="id", lx=18, ly=0),
    dict(x1=805, y1=210, x2=805, y2=250, bidir=True, label="key", lx=22, ly=0),
    dict(x1=680, y1=290, x2=580, y2=215, amber=True, label="the same object", lx=-10, ly=26),
]
notes = [
    dict(x=475, y=340, text="The id is the contract: a client stores it, compares it and sends it back, and never parses it.", anchor="middle", size=12, color="#555555"),
    dict(x=475, y=358, text="An unknown id resolves to null, and nodes keeps that null at its position in the list.", anchor="middle", size=12, color="#555555"),
]
g.emit("10-node-identity", 950, 375, nodes=nodes, edges=edges, notes=notes)
