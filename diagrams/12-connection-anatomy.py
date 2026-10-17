"""Spec for assets/diagrams/12-connection-anatomy.{svg,excalidraw}. Regenerate: python3 -I diagrams/12-connection-anatomy.py

The shape is the canonical SDL (contracts/schema/shipping/*.graphql) and the live
introspection result of both stacks, which verify.sh diffs against it. The amber
box is the one nullable link in the chain: CargoEdge.node, the fuse that lets one
failed item null its own edge instead of the page.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=330, label="Query.cargos(first, after, last, before, routingStatus): CargoConnection!"),
]
nodes = [
    dict(x=45, y=100, w=230, h=120, style="box", lines=["CargoConnection", "edges: [CargoEdge!]!", "pageInfo: PageInfo!", "totalCount: Int"]),
    dict(x=370, y=100, w=230, h=100, style="box", lines=["CargoEdge", "cursor: String!", "node: Cargo"]),
    dict(x=700, y=100, w=250, h=100, style="box", lines=["Cargo", "trackingId, description, ...", "handlingHistory: connection"]),
    dict(x=370, y=124, w=1, h=1, style="sub", lines=[""]),
    dict(x=45, y=255, w=230, h=100, style="accent", lines=["PageInfo", "hasNextPage: Boolean!", "hasPreviousPage: Boolean!"]),
    dict(x=370, y=255, w=230, h=100, style="sub", lines=["PageInfo, continued", "startCursor: String", "endCursor: String"]),
    dict(x=700, y=255, w=250, h=100, style="accent", lines=["node is nullable", "a Cargo that fails to load", "nulls its own edge only"]),
]
nodes.pop(3)
edges = [
    dict(x1=275, y1=135, x2=370, y2=135, label="edges", lx=0, ly=-10),
    dict(x1=600, y1=135, x2=700, y2=135, label="node", lx=0, ly=-10, amber=True),
    dict(x1=160, y1=220, x2=160, y2=255, label="pageInfo", lx=34, ly=4),
    dict(x1=725, y1=255, x2=725, y2=200, amber=True),
]
notes = [
    dict(x=500, y=28, text="A connection is a page of edges, a cursor on each edge, and the page's own metadata", anchor="middle", bold=True),
    dict(x=500, y=404, text="Null at startCursor and endCursor means the page is empty. totalCount is nullable because counting can be too costly to promise.", anchor="middle", size=12, color="#555555"),
]
g.emit("12-connection-anatomy", 1000, 430, bands=bands, nodes=nodes, edges=edges, notes=notes)
