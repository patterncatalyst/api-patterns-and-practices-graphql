"""Spec for assets/diagrams/21-sse-resume.{svg,excalidraw}. Regenerate: python3 -I diagrams/21-sse-resume.py

The plain SSE feed's resume. The reconnect, the replayed ids and the live id are
those of examples/21-real-time/verify.sh case 8 on the Quarkus stack: a client whose
last event was evt_10 reconnects with Last-Event-ID: evt_10 and receives evt_12 to
evt_18 in registration order, then evt_19 live, with no id twice.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=120, label="1  Connected: the feed names each event"),
    dict(x=20, y=190, w=960, h=110, label="2  Dropped: the store keeps what nobody heard"),
    dict(x=20, y=320, w=960, h=200, label="3  Reconnected: replay, then live"),
]
nodes = [
    dict(x=40, y=90, w=250, h=64, style="user", lines=["GET /events/cargos/ABC123", "Accept: text/event-stream"]),
    dict(x=370, y=90, w=290, h=64, style="accent", lines=["id: evt_10  event: handled", "data: {id, trackingId, type, ...}"]),
    dict(x=740, y=90, w=220, h=64, style="box", lines=["the client remembers", "Last-Event-ID = evt_10"]),
    dict(x=40, y=232, w=250, h=56, style="ink", lines=["connection lost", "the watcher leaves"]),
    dict(x=370, y=232, w=590, h=56, style="box", lines=["events registered for ABC123 meanwhile are stored", "evt_12 to evt_18"]),
    dict(x=40, y=362, w=250, h=64, style="user", lines=["GET /events/cargos/ABC123", "Last-Event-ID: evt_10"]),
    dict(x=370, y=362, w=290, h=64, style="box", lines=["1  join the broadcast", "so no live event can slip by"]),
    dict(x=690, y=362, w=270, h=64, style="accent", lines=["2  replay in registration order", "evt_12 to evt_18"]),
    dict(x=740, y=450, w=220, h=56, style="accent", lines=["3  live", "evt_19"]),
    dict(x=370, y=450, w=290, h=56, style="box", lines=["drop live ids already replayed", "no id is sent twice"]),
]
edges = [
    dict(x1=290, y1=122, x2=370, y2=122, label="200", lx=0, ly=-8),
    dict(x1=660, y1=122, x2=740, y2=122, amber=True),
    dict(x1=290, y1=260, x2=370, y2=260, dashed=True),
    dict(x1=290, y1=394, x2=370, y2=394),
    dict(x1=660, y1=394, x2=690, y2=394, amber=True),
    dict(x1=850, y1=426, x2=850, y2=450, amber=True),
    dict(x1=740, y1=478, x2=660, y2=478, dashed=True),
]
notes = [
    dict(x=500, y=28, text="Resume is a header and a store, not a protocol", anchor="middle", bold=True),
    dict(x=500, y=544, text="EventSource reconnects by itself and sends the last id it saw. A GraphQL subscription has no such id: the client subscribes again.", anchor="middle", size=12, color="#555555"),
]
g.emit("21-sse-resume", 1000, 570, bands=bands, nodes=nodes, edges=edges, notes=notes)
