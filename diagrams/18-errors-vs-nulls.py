"""Spec for assets/diagrams/18-errors-vs-nulls.{svg,excalidraw}. Regenerate: python3 -I diagrams/18-errors-vs-nulls.py

Two responses from one run of examples/18-authn-authz/verify.sh on the Python
stack. Left: ana asks for registrationTime on ABC123's two events (case 7).
Right: ana asks for a cargo that GLOBEX owns (case 4).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=560, h=400, label="A refused field: an error and a null node"),
    dict(x=600, y=50, w=380, h=400, label="A refused object: only a null"),
]
nodes = [
    dict(x=45, y=90, w=510, h=56, style="box", lines=["handlingHistory(first: 2) with node { id registrationTime }", "cargo(ABC123), as ana (a shipper, not an operator)"]),
    dict(x=45, y=180, w=240, h=56, style="accent", lines=["edges[0].node = null", "cursor survives"]),
    dict(x=315, y=180, w=240, h=56, style="accent", lines=["edges[1].node = null", "cursor survives"]),
    dict(x=45, y=270, w=510, h=70, style="ink", lines=["2 errors, code FORBIDDEN, operator role required", "paths cargo, handlingHistory, edges, 0|1, node, registrationTime"]),
    dict(x=45, y=370, w=510, h=56, style="box", lines=["DateTime! cannot be null, so the null climbs one step", "to the nullable node; the page and cargo survive"]),
    dict(x=625, y=90, w=330, h=56, style="box", lines=["cargo(XYZ789) { trackingId }", "as ana (ACME); XYZ789 is GLOBEX's"]),
    dict(x=625, y=180, w=330, h=56, style="accent", lines=["data.cargo = null", "no errors"]),
    dict(x=625, y=270, w=330, h=70, style="box", lines=["cargo(ZZZ999) gives the identical body", "the caller cannot enumerate other shippers"]),
]
edges = [
    dict(x1=165, y1=146, x2=165, y2=180),
    dict(x1=435, y1=146, x2=435, y2=180),
    dict(x1=165, y1=236, x2=165, y2=270, amber=True),
    dict(x1=435, y1=236, x2=435, y2=270, amber=True),
    dict(x1=290, y1=340, x2=290, y2=370),
    dict(x1=790, y1=146, x2=790, y2=180),
    dict(x1=790, y1=236, x2=790, y2=270),
]
notes = [
    dict(x=500, y=28, text="Fields: error. Objects: null.", anchor="middle", bold=True),
    dict(x=500, y=474, text="A field that exists but is not yours says so. An object that is not yours looks like one that does not exist.", anchor="middle", size=12, color="#555555"),
]
g.emit("18-errors-vs-nulls", 1000, 500, bands=bands, nodes=nodes, edges=edges, notes=notes)
