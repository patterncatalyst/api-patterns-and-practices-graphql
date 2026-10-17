"""Spec for assets/diagrams/06-field-walk.{svg,excalidraw}. Regenerate: python3 -I diagrams/06-field-walk.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# The field tree of the query in the chapter, with the five resolver
# invocations numbered in the order they start and the parent value handed
# down each edge.
nodes = [
    dict(x=20, y=170, w=110, h=60, style="box", lines=["Query", "root value"]),
    dict(x=180, y=170, w=220, h=60, style="accent", lines=["1  cargo", "booking.getCargo(ABC123)"]),
    dict(x=470, y=80, w=230, h=60, style="accent", lines=["2  itinerary", "routing.getItinerary(ABC123)"]),
    dict(x=470, y=300, w=230, h=60, style="accent", lines=["3  delivery", "delivery.getDelivery(ABC123)"]),
    dict(x=770, y=80, w=110, h=60, style="box", lines=["legs", "no source call"]),
    dict(x=960, y=20, w=230, h=60, style="accent", lines=["4  legs[0].loadLocation", "location.getLocation(USNYC)"]),
    dict(x=960, y=140, w=230, h=60, style="accent", lines=["5  legs[1].loadLocation", "location.getLocation(DEHAM)"]),
]
edges = [
    dict(x1=130, y1=200, x2=180, y2=200, label="root", ly=-8),
    dict(x1=400, y1=190, x2=470, y2=115, label="Cargo", lx=-12, ly=-14),
    dict(x1=400, y1=210, x2=470, y2=325, label="Cargo", lx=-12, ly=24),
    dict(x1=700, y1=110, x2=770, y2=110, label="Itinerary", ly=-10),
    dict(x1=880, y1=100, x2=960, y2=50, label="Leg 0", lx=-22, ly=-10),
    dict(x1=880, y1=120, x2=960, y2=170, label="Leg 1", lx=-22, ly=24),
]
notes = [
    dict(x=585, y=388, text="2 and 3 start together once 1 returns; 4 and 5 start together once 2 returns", anchor="middle", size=12, color="#555555"),
    dict(x=585, y=410, text="Each box is a resolver call. The label on an edge is the parent value it receives.", anchor="middle", size=12, color="#555555"),
    dict(x=585, y=44, text="Field walk for cargo { itinerary { legs { loadLocation } } delivery }", anchor="middle", bold=True),
]
g.emit("06-field-walk", 1210, 430, nodes=nodes, edges=edges, notes=notes)
