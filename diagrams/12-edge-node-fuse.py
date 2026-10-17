"""Spec for assets/diagrams/12-edge-node-fuse.{svg,excalidraw}. Regenerate: python3 -I diagrams/12-edge-node-fuse.py

The response is page 3 of cargos(first: 2) as both stacks return it (the key order
of data and errors differs by stack and carries no meaning): edge 0 is ABC123,
edge 1 is GHI345, whose booking.getCargo fails. The values are the ones verify.sh
asserts.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=500, h=330, label="data.cargos"),
    dict(x=560, y=50, w=420, h=330, label="errors"),
]
nodes = [
    dict(x=50, y=90, w=440, h=60, style="box", lines=["edges[0]", "cursor ...QUJDMTIz, node.trackingId ABC123"]),
    dict(x=50, y=170, w=440, h=60, style="box", lines=["edges[1].cursor", "kept: ...R0hJMzQ1"]),
    dict(x=50, y=240, w=440, h=60, style="accent", lines=["edges[1].node: null", "the fuse: only this edge lost its item"]),
    dict(x=50, y=312, w=440, h=56, style="box", lines=["pageInfo and totalCount", "hasNextPage false, hasPreviousPage true; totalCount 6"]),
    dict(x=590, y=150, w=360, h=110, style="accent", lines=["errors[0]", "booking service unavailable", "code SERVICE_UNAVAILABLE", 'path ["cargos","edges",1,"node"]']),
]
edges = [dict(x1=590, y1=230, x2=490, y2=270, amber=True, label="path", lx=0, ly=-10)]
notes = [
    dict(x=500, y=28, text="One bad node, one null edge: the page, its cursors and pageInfo survive", anchor="middle", bold=True),
    dict(x=500, y=404, text="node is nullable, so the null stops at the edge. A non-null node would climb to the page, then to data.", anchor="middle", size=12, color="#555555"),
]
g.emit("12-edge-node-fuse", 1000, 430, bands=bands, nodes=nodes, edges=edges, notes=notes)
