"""Spec for assets/diagrams/21-event-path.{svg,excalidraw}. Regenerate: python3 -I diagrams/21-event-path.py

One registration, drawn from one run of examples/21-real-time/verify.sh (case 3, the
Python stack): REG_A1 registers evt_10 for ABC123 while one subscriber watches
ABC123 and one watches DEF456. The four reads in the box are the source-call log of
that event's execution: one bulk call each, under the subscription's request id.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=430, label="From a registration to a frame")]
nodes = [
    dict(x=40, y=100, w=190, h=84, style="user", lines=["registerHandlingEvent", "ABC123 UNLOAD DEHAM V100S", "a mutation over HTTP"]),
    dict(x=270, y=100, w=190, h=84, style="box", lines=["handling store", "append evt_10", "not for an idempotent replay"]),
    dict(x=500, y=100, w=190, h=84, style="box", lines=["broadcast", "a bounded queue per watcher", "Mutiny processor | asyncio.Queue"]),
    dict(x=740, y=82, w=220, h=56, style="ghost", lines=["watcher: DEF456", "no match: nothing sent"]),
    dict(x=740, y=164, w=220, h=56, style="accent", lines=["watcher: ABC123", "match: tracking id ABC123"]),
    dict(x=700, y=280, w=260, h=130, style="box", lines=["execute the selection set", "location.getLocations DEHAM", "booking.getCargos ABC123", "routing.getItineraries ABC123", "handling.listEventsFor ABC123"]),
    dict(x=360, y=300, w=290, h=90, style="ink", lines=["next frame, or SSE event", "evt_10, Hamburg, IN_PORT", "one per event, in order"]),
    dict(x=40, y=300, w=270, h=90, style="user", lines=["subscriber", "receives evt_10, then evt_12", "DEF456's event never arrives"]),
]
edges = [
    dict(x1=230, y1=142, x2=270, y2=142, label="HTTP", lx=0, ly=-8),
    dict(x1=460, y1=142, x2=500, y2=142, amber=True),
    dict(x1=690, y1=122, x2=740, y2=112, dashed=True),
    dict(x1=690, y1=162, x2=740, y2=192, amber=True),
    dict(x1=850, y1=220, x2=850, y2=280, amber=True, label="one execution", lx=50, ly=0),
    dict(x1=700, y1=345, x2=650, y2=345, amber=True, label="encode", lx=0, ly=-8),
    dict(x1=360, y1=345, x2=310, y2=345, amber=True),
]
notes = [
    dict(x=500, y=28, text="Each event is an execution of the subscriber's own selection set", anchor="middle", bold=True),
    dict(x=500, y=504, text="In process here; with several server instances a message broker carries the event to every instance's watchers. The loaders are emptied between events.", anchor="middle", size=12, color="#555555"),
]
g.emit("21-event-path", 1000, 530, bands=bands, nodes=nodes, edges=edges, notes=notes)
