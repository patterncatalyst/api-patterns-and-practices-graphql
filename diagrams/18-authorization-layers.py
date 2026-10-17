"""Spec for assets/diagrams/18-authorization-layers.{svg,excalidraw}. Regenerate: python3 -I diagrams/18-authorization-layers.py

The three places a rule is stated in examples/18-authn-authz and what a refusal
looks like at each (verify.sh asserts every one on both stacks).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=300, h=400, label="Operation"),
    dict(x=340, y=50, w=320, h=400, label="Object"),
    dict(x=680, y=50, w=300, h=400, label="Field"),
]
nodes = [
    dict(x=40, y=90, w=260, h=80, style="box", lines=["@Authenticated, @RolesAllowed", "IsAuthenticated, IsOperator", "on cargo, cargos, registerHandlingEvent"]),
    dict(x=40, y=200, w=260, h=60, style="accent", lines=["refusal: an error with a code", "UNAUTHENTICATED or FORBIDDEN"]),
    dict(x=40, y=290, w=260, h=70, style="box", lines=["no source is called", "cargo nulls itself;", "cargos and the mutation null data"]),
    dict(x=360, y=90, w=280, h=60, style="box", lines=["cargo, cargos + totalCount, node,", "nodes, edge node, HandlingEvent.cargo"]),
    dict(x=360, y=190, w=280, h=70, style="ink", lines=["BookingSource", "the one place the owner is checked"]),
    dict(x=360, y=290, w=280, h=70, style="accent", lines=["refusal: null, no error", "the same answer as an unknown id"]),
    dict(x=700, y=90, w=260, h=70, style="box", lines=["HandlingEvent.registrationTime", "operator only"]),
    dict(x=685, y=190, w=290, h=60, style="accent", lines=["refusal: FORBIDDEN at the field's path", "operator role required"]),
    dict(x=700, y=290, w=260, h=70, style="box", lines=["the null climbs to the nearest", "nullable parent: the edge's node"]),
]
edges = [
    dict(x1=170, y1=170, x2=170, y2=200),
    dict(x1=170, y1=260, x2=170, y2=290),
    dict(x1=500, y1=150, x2=500, y2=190, amber=True),
    dict(x1=500, y1=260, x2=500, y2=290),
    dict(x1=830, y1=160, x2=830, y2=190),
    dict(x1=830, y1=250, x2=830, y2=290),
]
notes = [
    dict(x=500, y=28, text="Where each rule refuses", anchor="middle", bold=True),
    dict(x=500, y=478, text="Operations and fields refuse with an error; objects refuse with a null, so a caller cannot tell absent from not yours.", anchor="middle", size=12, color="#555555"),
]
g.emit("18-authorization-layers", 1000, 500, bands=bands, nodes=nodes, edges=edges, notes=notes)
