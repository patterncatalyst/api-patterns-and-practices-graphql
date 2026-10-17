"""Spec for assets/diagrams/07-resolver-chain.{svg,excalidraw}. Regenerate: python3 -I diagrams/07-resolver-chain.py

The millisecond offsets are the source-call log of one real run of the chapter's
first query on the Quarkus stack, relative to the start of booking.getCargo.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

# Row of alternating resolvers (accent) and the values they return (box); the
# source each resolver calls hangs below it (sub). Keys label the arrows.
nodes = [
    dict(x=20, y=130, w=190, h=60, style="accent", lines=["1  Query.cargo", "arg trackingId ABC123"]),
    dict(x=270, y=130, w=150, h=60, style="box", lines=["Cargo", "trackingId ABC123"]),
    dict(x=480, y=130, w=190, h=60, style="accent", lines=["2  Cargo.itinerary", "parent trackingId"]),
    dict(x=730, y=130, w=160, h=60, style="box", lines=["Itinerary", "2 legs"]),
    dict(x=960, y=50, w=200, h=60, style="accent", lines=["3  legs[0].voyage", "parent voyageNumber"]),
    dict(x=960, y=210, w=200, h=60, style="accent", lines=["3  legs[1].voyage", "parent voyageNumber"]),
    dict(x=1250, y=50, w=220, h=60, style="sub", lines=["voyage.getVoyage(V100S)", "+522 to +773 ms"]),
    dict(x=1250, y=210, w=220, h=60, style="sub", lines=["voyage.getVoyage(V200E)", "+522 to +776 ms"]),
    dict(x=20, y=290, w=190, h=60, style="sub", lines=["booking.getCargo(ABC123)", "+0 to +254 ms"]),
    dict(x=460, y=290, w=230, h=60, style="sub", lines=["routing.getItinerary(ABC123)", "+265 to +516 ms"]),
]
edges = [
    dict(x1=115, y1=190, x2=115, y2=290, bidir=True, label="key ABC123", lx=44, ly=0),
    dict(x1=210, y1=160, x2=270, y2=160, label="returns", ly=-10),
    dict(x1=420, y1=160, x2=480, y2=160, amber=True, label="parent", ly=-10),
    dict(x1=575, y1=190, x2=575, y2=290, bidir=True, label="key ABC123", lx=44, ly=0),
    dict(x1=670, y1=160, x2=730, y2=160, label="returns", ly=-10),
    dict(x1=890, y1=145, x2=960, y2=80, amber=True, label="leg 0", lx=-18, ly=-10),
    dict(x1=890, y1=175, x2=960, y2=240, amber=True, label="leg 1", lx=-18, ly=24),
    dict(x1=1160, y1=80, x2=1250, y2=80, bidir=True, label="V100S", ly=-12),
    dict(x1=1160, y1=240, x2=1250, y2=240, bidir=True, label="V200E", ly=-12),
]
notes = [
    dict(x=745, y=28, text="The resolver chain for cargo { itinerary { legs { voyage { number } } } }", anchor="middle", bold=True),
    dict(x=745, y=388, text="Each arrow into a resolver carries the parent value it receives. Each arrow to a source carries the key the resolver derived from it.", anchor="middle", size=12, color="#555555"),
    dict(x=745, y=408, text="The two voyage resolvers start together: list items resolve concurrently. Offsets are from one Quarkus run's source-call log.", anchor="middle", size=12, color="#555555"),
]
g.emit("07-resolver-chain", 1490, 430, nodes=nodes, edges=edges, notes=notes)
