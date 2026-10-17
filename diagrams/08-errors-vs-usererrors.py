"""Spec for assets/diagrams/08-errors-vs-usererrors.{svg,excalidraw}. Regenerate: python3 -I diagrams/08-errors-vs-usererrors.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=500, h=330, label="Coercion failure: type is TELEPORT"),
    dict(x=560, y=50, w=500, h=330, label="Domain failure: LOAD without a voyage"),
]
nodes = [
    dict(x=50, y=90, w=440, h=62, style="ghost", lines=["data", "absent on Quarkus, null on Strawberry"]),
    dict(x=50, y=172, w=440, h=84, style="accent", lines=["errors[0]", "message names the bad value", "locations point into the document", "no path: no field ran"]),
    dict(x=50, y=276, w=440, h=84, style="sub", lines=["Raised by the engine", "before the resolver runs", "HTTP 200 on both stacks"]),
    dict(x=590, y=90, w=440, h=84, style="accent", lines=["data.registerHandlingEvent", "handlingEvent: null", "cargo: null"]),
    dict(x=590, y=194, w=440, h=62, style="accent", lines=["userErrors[0]", 'code VOYAGE_REQUIRED, field ["input", "voyageNumber"]']),
    dict(x=590, y=276, w=440, h=84, style="sub", lines=["Returned by the resolver", "as an ordinary value", "no errors key at all"]),
]
notes = [
    dict(x=540, y=28, text="Two kinds of failure, two places in the response", anchor="middle", bold=True),
    dict(x=540, y=404, text="A client reads errors[] to learn the request was malformed, and userErrors to learn the input was refused.", anchor="middle", size=12, color="#555555"),
]
g.emit("08-errors-vs-usererrors", 1080, 430, bands=bands, nodes=nodes, notes=notes)
