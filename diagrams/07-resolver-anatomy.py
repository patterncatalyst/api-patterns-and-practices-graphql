"""Spec for assets/diagrams/07-resolver-anatomy.{svg,excalidraw}. Regenerate: python3 -I diagrams/07-resolver-anatomy.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Four inputs, each with its Java and Python spelling, feed one resolver:
# Cargo.itinerary, the field that asks the routing source for a cargo's legs.
# Edge labels sit beside their line, never on it (lx/ly for the SVG, elx/ely for
# the Excalidraw text, which is left-aligned).
nodes = [
    dict(x=20, y=50, w=400, h=88, style="box", lines=["parent", "the object this field is selected on", "Java: @Source Cargo cargo", "Python: self"]),
    dict(x=20, y=168, w=400, h=88, style="box", lines=["arguments", "values written in the document", "Java: named parameters", "Python: typed parameters"]),
    dict(x=20, y=276, w=400, h=88, style="box", lines=["context", "per request: request id, sources", "Java: Context context, built by SmallRye", "Python: info.context, built by context_getter"]),
    dict(x=20, y=384, w=400, h=88, style="box", lines=["info", "field name, path, selected fields", "Java: the same Context (getPath, getSelectedFields)", "Python: info (path, selected_fields)"]),
    dict(x=520, y=190, w=250, h=124, style="accent", lines=["Cargo.itinerary", "reads the tracking id", "from the parent", "calls routing.getItinerary"]),
    dict(x=900, y=190, w=210, h=124, style="box", lines=["return value", "Itinerary or null", "Java: Uni of Itinerary", "Python: coroutine"]),
]
edges = [
    dict(x1=420, y1=94, x2=520, y2=235, amber=True, label="ABC123", lx=30, ly=-10, elx=12, ely=-7),
    dict(x1=420, y1=212, x2=520, y2=252, label="none here", lx=-15, ly=26, elx=-42, ely=29),
    dict(x1=420, y1=320, x2=520, y2=270, label="request id", lx=-15, ly=38, elx=-45, ely=41),
    dict(x1=420, y1=428, x2=520, y2=290, label="seldom needed", lx=50, ly=10, elx=11, ely=13),
    dict(x1=770, y1=252, x2=900, y2=252, amber=True, label="engine completes it", lx=0, ly=-12),
]
notes = [
    dict(x=560, y=36, text="Four inputs to one resolver", anchor="middle", bold=True),
    dict(x=560, y=500, text="The amber arrows carry the data this resolver uses. Cargo.itinerary takes no arguments; Query.cargo takes trackingId.", anchor="middle", size=12, color="#555555"),
]
g.emit("07-resolver-anatomy", 1130, 520, nodes=nodes, edges=edges, notes=notes)
