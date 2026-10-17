"""Spec for assets/diagrams/06-response-assembly.{svg,excalidraw}. Regenerate: python3 -I diagrams/06-response-assembly.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Left: resolver results in the order they completed. Middle: the slots of the
# response, in the order of the selection, named by alias. Right: the response.
nodes = [
    dict(x=20, y=90, w=290, h=70, style="box", lines=["Finished 1st", "a: cargo(ABC123)", "returned Cargo ABC123"]),
    dict(x=20, y=230, w=290, h=70, style="box", lines=["Finished 2nd", "b: cargo(XYZ789)", "returned Cargo XYZ789"]),
    dict(x=450, y=90, w=250, h=62, style="accent", lines=['"b"', "first in the selection"]),
    dict(x=450, y=238, w=250, h=62, style="accent", lines=['"a"', "second in the selection"]),
    dict(x=830, y=140, w=290, h=70, style="box", lines=['{ "data": { "b": {...}, "a": {...} } }', "keys in selection order,", "named by alias"]),
    dict(x=830, y=290, w=290, h=62, style="ghost", lines=['"errors": [ { message, path } ]', "only when a resolver failed"]),
]
edges = [
    dict(x1=310, y1=125, x2=450, y2=270, amber=True),
    dict(x1=310, y1=265, x2=450, y2=121, amber=True),
    dict(x1=700, y1=121, x2=830, y2=165, amber=True),
    dict(x1=700, y1=269, x2=830, y2=185, amber=True),
    dict(x1=975, y1=290, x2=975, y2=210, dashed=True, label="path names the failed field", lx=0, ly=-8),
]
notes = [
    dict(x=570, y=44, text="Completion order does not matter: the response follows the selection", anchor="middle", bold=True),
    dict(x=570, y=360, text="Execution errors sit beside data, never inside it: data keeps every field that did resolve.", anchor="middle", size=12, color="#555555"),
]
g.emit("06-response-assembly", 1140, 390, nodes=nodes, edges=edges, notes=notes)
