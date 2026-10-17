"""Spec for assets/diagrams/20-subgraph-ownership.{svg,excalidraw}. Regenerate: python3 -I diagrams/20-subgraph-ownership.py

The canonical types laid out by the subgraph that owns them, as examples/20-federation
serves them on both stacks: the entities and their keys, the references (dashed,
resolvable: false), and the types both subgraphs define identically.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=340, h=400, label="cargo subgraph (booking and routing team)"),
    dict(x=640, y=50, w=340, h=400, label="handling subgraph (handling team)"),
    dict(x=20, y=462, w=960, h=100, label="defined in both subgraphs, identically"),
]
nodes = [
    dict(x=40, y=80, w=300, h=90, style="accent", lines=["Cargo @key(fields: \"trackingId\")", "id, trackingId, description, origin,", "destination, routeSpecification, itinerary"]),
    dict(x=40, y=190, w=300, h=60, style="box", lines=["Location @key(fields: \"unLocode\")", "id, unLocode, name, country"]),
    dict(x=40, y=265, w=300, h=60, style="box", lines=["Voyage @key(fields: \"number\")", "id, number, schedule"]),
    dict(x=40, y=340, w=300, h=90, style="sub", lines=["Query.cargo, cargos, location, voyage", "Itinerary, Leg, RouteSpecification", "CargoConnection, CargoEdge, CarrierMovement"]),
    dict(x=40, y=490, w=290, h=60, style="sub", lines=["PageInfo @shareable", "the same four fields"]),
    dict(x=355, y=490, w=290, h=60, style="sub", lines=["Node, the scalars", "descriptions copied verbatim"]),
    dict(x=670, y=490, w=290, h=60, style="sub", lines=["RoutingStatus", "an identical enum"]),
    dict(x=660, y=80, w=300, h=90, style="accent", lines=["Cargo @key(fields: \"trackingId\")", "trackingId, delivery,", "handlingHistory"]),
    dict(x=660, y=190, w=300, h=60, style="box", lines=["HandlingEvent @key(fields: \"id\")", "implements Node, every field"]),
    dict(x=660, y=265, w=300, h=60, style="ghost", lines=["Location @key(unLocode, resolvable: false)", "unLocode only"]),
    dict(x=660, y=340, w=300, h=50, style="ghost", lines=["Voyage @key(number, resolvable: false)", "number only"]),
    dict(x=660, y=396, w=300, h=46, style="sub", lines=["Mutation.registerHandlingEvent", "Delivery, HandlingActivity, UserError"]),
]
edges = [
    dict(x1=340, y1=125, x2=660, y2=125, amber=True, bidir=True, label="the same entity, the same key", lx=0, ly=-10),
    dict(x1=660, y1=295, x2=340, y2=225, dashed=True, label="reference", lx=40, ly=-10),
    dict(x1=660, y1=365, x2=340, y2=300, dashed=True, label="reference", lx=40, ly=14),
]
notes = [
    dict(x=500, y=28, text="Each field has one owner; an entity is shared by its key, a reference names a place and nothing else", anchor="middle", bold=True),
    dict(x=40, y=585, text="A reference carries only the key. The handling subgraph can say where an event happened; the name of the place is the cargo subgraph's to resolve.", size=12, color="#555555"),
]
g.emit("20-subgraph-ownership", 1000, 610, bands=bands, nodes=nodes, edges=edges, notes=notes)
