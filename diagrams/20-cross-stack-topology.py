"""Spec for assets/diagrams/20-cross-stack-topology.{svg,excalidraw}. Regenerate: python3 -I diagrams/20-cross-stack-topology.py

The ports of examples/20-federation/compose.yaml: two gateways, each composed over
one subgraph from each stack, so every stack is both the cargo owner and the
handling owner somewhere.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=380, label="Two supergraphs over the same four subgraph contracts")]
nodes = [
    dict(x=330, y=80, w=340, h=55, style="user", lines=["client", "one query, either gateway"]),
    dict(x=130, y=190, w=240, h=70, style="accent", lines=["gateway-a", "supergraph-a, host 8300"]),
    dict(x=630, y=190, w=240, h=70, style="accent", lines=["gateway-b", "supergraph-b, host 8301"]),
    dict(x=40, y=340, w=200, h=70, style="box", lines=["cargo on Quarkus", "SmallRye, host 8302"]),
    dict(x=270, y=340, w=200, h=70, style="accent", lines=["cargo on Python", "Strawberry, host 8303"]),
    dict(x=530, y=340, w=200, h=70, style="box", lines=["handling on Quarkus", "SmallRye, host 8304"]),
    dict(x=760, y=340, w=200, h=70, style="accent", lines=["handling on Python", "Strawberry, host 8305"]),
]
edges = [
    dict(x1=480, y1=135, x2=300, y2=190, dashed=True),
    dict(x1=520, y1=135, x2=700, y2=190, dashed=True),
    dict(x1=170, y1=260, x2=140, y2=340, amber=True),
    dict(x1=330, y1=260, x2=830, y2=340, amber=True),
    dict(x1=670, y1=260, x2=380, y2=340, amber=True),
    dict(x1=830, y1=260, x2=630, y2=340, amber=True),
]
notes = [
    dict(x=500, y=28, text="The subgraph contract is stack-neutral: either stack can own either subgraph", anchor="middle", bold=True),
    dict(x=40, y=455, text="Each gateway reaches the cargo and the handling subgraph of its own pair. Composition runs once per pair.", size=12, color="#555555"),
    dict(x=40, y=473, text="White boxes are Quarkus with SmallRye GraphQL; amber boxes are Python with Strawberry.", size=12, color="#555555"),
]
g.emit("20-cross-stack-topology", 1000, 495, bands=bands, nodes=nodes, edges=edges, notes=notes)
