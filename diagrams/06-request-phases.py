"""Spec for assets/diagrams/06-request-phases.{svg,excalidraw}. Regenerate: python3 -I diagrams/06-request-phases.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# One row of stages left to right. The three request-error stages each have an
# exit arrow down to one outcome box; only Execute reaches the sources.
Y, H, W = 70, 84, 140
xs = [20, 200, 380, 560, 750, 940]
nodes = [
    dict(x=xs[0], y=Y, w=W, h=H, style="user", lines=["POST /graphql", "query, variables,", "operationName"]),
    dict(x=xs[1], y=Y, w=W, h=H, style="box", lines=["Parse", "text to a document", "(syntax)"]),
    dict(x=xs[2], y=Y, w=W, h=H, style="box", lines=["Validate", "document against", "the schema"]),
    dict(x=xs[3], y=Y, w=W + 20, h=H, style="box", lines=["Coerce variables", "JSON values to", "declared types"]),
    dict(x=xs[4], y=Y, w=W, h=H, style="accent", lines=["Execute", "walk the selection,", "call resolvers"]),
    dict(x=xs[5], y=Y, w=W, h=H, style="user", lines=["Response", "data, errors,", "or both"]),
    dict(x=200, y=250, w=500, h=74, style="accent", lines=["Request error", "errors, no data, and zero source calls: nothing ran, so a retry is safe"]),
    dict(x=750, y=250, w=W, h=74, style="box", lines=["Sources", "booking, routing,", "voyage, location, delivery"]),
]
edges = [
    dict(x1=xs[0] + W, y1=Y + H / 2, x2=xs[1], y2=Y + H / 2),
    dict(x1=xs[1] + W, y1=Y + H / 2, x2=xs[2], y2=Y + H / 2),
    dict(x1=xs[2] + W, y1=Y + H / 2, x2=xs[3], y2=Y + H / 2),
    dict(x1=xs[3] + W + 20, y1=Y + H / 2, x2=xs[4], y2=Y + H / 2),
    dict(x1=xs[4] + W, y1=Y + H / 2, x2=xs[5], y2=Y + H / 2, amber=True),
    dict(x1=xs[1] + W / 2, y1=Y + H, x2=xs[1] + W / 2, y2=250, dashed=True),
    dict(x1=xs[2] + W / 2, y1=Y + H, x2=xs[2] + W / 2, y2=250, dashed=True),
    dict(x1=xs[3] + W / 2 + 10, y1=Y + H, x2=xs[3] + W / 2 + 10, y2=250, dashed=True),
    dict(x1=xs[4] + W / 2, y1=Y + H, x2=xs[4] + W / 2, y2=250, amber=True, bidir=True, label="resolver calls", lx=52, ly=4),
]
notes = [
    dict(x=490, y=34, text="Three stages run before any resolver; a failure in any of them ends the request", anchor="middle", bold=True),
    dict(x=490, y=360, text="Execution errors are different: they arrive beside partial data from the Execute stage.", anchor="middle", size=12, color="#555555"),
]
g.emit("06-request-phases", 1100, 380, nodes=nodes, edges=edges, notes=notes)
