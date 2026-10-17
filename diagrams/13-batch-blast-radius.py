"""Spec for assets/diagrams/13-batch-blast-radius.{svg,excalidraw}. Regenerate: python3 -I diagrams/13-batch-blast-radius.py

The response to cargos(last: 2) { edges { node { trackingId } } } as each stack
returns it (verify.sh asserts both): the last page is ABC123 and GHI345, and one
bulk booking.getCargos call carries both keys, with GHI345 failing.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=470, h=400, label="Strawberry: an exception instance at one position"),
    dict(x=510, y=50, w=470, h=400, label="SmallRye: one result list for the batch"),
]
nodes = [
    dict(x=45, y=95, w=420, h=56, style="box", lines=["booking.getCargos ABC123+GHI345", "GHI345 fails"]),
    dict(x=45, y=185, w=420, h=56, style="box", lines=["load_fn returns [Cargo ABC123, SourceUnavailable]", "the instance is placed at its key's position"]),
    dict(x=45, y=275, w=200, h=56, style="box", lines=["edges[0].node", "ABC123 resolved"]),
    dict(x=265, y=275, w=200, h=56, style="accent", lines=["edges[1].node", "null"]),
    dict(x=45, y=365, w=420, h=60, style="accent", lines=["1 error, path cargos, edges, 1, node", "code SERVICE_UNAVAILABLE"]),
    dict(x=535, y=95, w=420, h=56, style="box", lines=["booking.getCargos ABC123+GHI345", "GHI345 fails"]),
    dict(x=535, y=185, w=420, h=56, style="box", lines=["the batch method fails its whole Uni", "every parent in the batch gets the failure"]),
    dict(x=535, y=275, w=200, h=56, style="accent", lines=["edges[0].node", "null (ABC123 lost)"]),
    dict(x=755, y=275, w=200, h=56, style="accent", lines=["edges[1].node", "null"]),
    dict(x=535, y=365, w=420, h=60, style="accent", lines=["2 errors, one per path", "code SERVICE_UNAVAILABLE at edges 0 and 1"]),
]
edges = [
    dict(x1=255, y1=151, x2=255, y2=185),
    dict(x1=150, y1=241, x2=145, y2=275),
    dict(x1=360, y1=241, x2=365, y2=275),
    dict(x1=255, y1=331, x2=255, y2=365, amber=True),
    dict(x1=745, y1=151, x2=745, y2=185),
    dict(x1=640, y1=241, x2=635, y2=275),
    dict(x1=850, y1=241, x2=855, y2=275),
    dict(x1=745, y1=331, x2=745, y2=365, amber=True),
]
notes = [
    dict(x=500, y=28, text="A failing key inside a batch: one null edge on Strawberry, the whole batch on SmallRye", anchor="middle", bold=True),
    dict(x=500, y=474, text="Both responses carry the same code and message. They differ in how many nodes the one failure takes with it.", anchor="middle", size=12, color="#555555"),
]
g.emit("13-batch-blast-radius", 1000, 500, bands=bands, nodes=nodes, edges=edges, notes=notes)
