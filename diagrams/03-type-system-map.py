"""Spec for assets/diagrams/03-type-system-map.{svg,excalidraw}. Regenerate: python3 -I diagrams/03-type-system-map.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

W = 140
def col(i):
    return 30 + i * 156

bands = [
    dict(x=20, y=20, w=940, h=96, label="Interface"),
    dict(x=20, y=136, w=940, h=170, label="Object types"),
    dict(x=20, y=326, w=940, h=92, label="Enums: closed sets, serialized as names"),
    dict(x=20, y=438, w=940, h=92, label="Scalars: leaves of every selection"),
    dict(x=20, y=550, w=940, h=92, label="Input types and wrappers"),
]
nodes = [
    dict(x=col(1), y=54, w=W, h=48, style="accent", lines=["Node", "id: ID!"]),
    # Row A: the three Node implementers
    dict(x=col(0), y=170, w=W, h=56, style="accent", lines=["Cargo", "implements Node"]),
    dict(x=col(1), y=170, w=W, h=56, style="accent", lines=["Location", "implements Node"]),
    dict(x=col(2), y=170, w=W, h=56, style="accent", lines=["Voyage", "implements Node"]),
    dict(x=col(3), y=170, w=W, h=56, style="box", lines=["RouteSpecification", "arrivalDeadline"]),
    dict(x=col(4), y=170, w=W, h=56, style="box", lines=["Itinerary", "legs: [Leg!]!"]),
    dict(x=col(5), y=170, w=W, h=56, style="box", lines=["Leg", "voyage: Voyage"]),
    # Row B
    dict(x=col(3), y=240, w=W, h=56, style="box", lines=["CarrierMovement", "departureTime"]),
    dict(x=col(4), y=240, w=W, h=56, style="box", lines=["Delivery", "transportStatus"]),
    dict(x=col(5), y=240, w=W, h=56, style="box", lines=["HandlingActivity", "type, location"]),
    # Enums
    dict(x=col(0), y=360, w=200, h=44, style="box", lines=["TransportStatus", "5 values"]),
    dict(x=col(2) + 44, y=360, w=200, h=44, style="box", lines=["RoutingStatus", "3 values"]),
    dict(x=col(4) + 12, y=360, w=200, h=44, style="box", lines=["HandlingEventType", "5 values"]),
    # Scalars
    dict(x=col(0), y=472, w=200, h=44, style="sub", lines=["String Int Float", "Boolean ID (built in)"]),
    dict(x=col(2) + 44, y=472, w=130, h=44, style="box", lines=["TrackingId", "custom"]),
    dict(x=col(3) + 74, y=472, w=130, h=44, style="box", lines=["UnLocode", "custom, @specifiedBy"]),
    dict(x=col(5) - 40, y=472, w=180, h=44, style="box", lines=["DateTime", "custom, @specifiedBy"]),
    # Input and wrappers
    dict(x=col(0), y=584, w=270, h=44, style="ghost", lines=["RegisterHandlingEventInput", "input type, served in Chapter 8"]),
    dict(x=col(3) - 20, y=584, w=330, h=44, style="sub", lines=["Wrappers: T!  [T]  [T!]!", "Itinerary.legs reads inside-out as [Leg!]!"]),
]
edges = [
    dict(x1=col(1) + 70, y1=102, x2=col(0) + 70, y2=170, amber=True),
    dict(x1=col(1) + 70, y1=102, x2=col(1) + 70, y2=170, amber=True, label="implements", lx=38, ly=2),
    dict(x1=col(1) + 70, y1=102, x2=col(2) + 70, y2=170, amber=True),
]
notes = [
    dict(x=490, y=12, text="The tracking view's types, grouped by kind", anchor="middle", bold=True),
]
g.emit("03-type-system-map", 980, 660, bands=bands, nodes=nodes, edges=edges, notes=notes)
