"""Spec for assets/diagrams/27-subscription-path.{svg,excalidraw}. Regenerate: python3 -I diagrams/27-subscription-path.py

Drawn from one run of examples/27-final-project. ana subscribes to ABC123 through the
edge over wss with her bearer token; bo is refused with FORBIDDEN and his subscription
never starts; ops registers REG_F1 (an UNLOAD of ABC123 at DEHAM, idempotency key
ch27-final-unload-1), which the handling store stores as evt_10 and broadcasts. The engine
executes the subscription's selection once for each subscriber, as that subscriber:
ana's registrationTime is FORBIDDEN, ops' is a value. The plain SSE feed beside it
applies the same rules and resumes from Last-Event-ID evt_9 with evt_10.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=470, label="One registration, heard by each subscriber under its own rights"),
]
nodes = [
    dict(x=40, y=90, w=160, h=70, style="user", lines=["ana (ACME)", "wss, bearer token", "subscribe ABC123"]),
    dict(x=40, y=190, w=160, h=70, style="user", lines=["bo (GLOBEX)", "wss, bearer token", "subscribe ABC123"]),
    dict(x=40, y=290, w=160, h=70, style="user", lines=["ana, plain feed", "GET /events/cargos/", "ABC123, evt_9"]),
    dict(x=40, y=410, w=160, h=70, style="user", lines=["ops", "mutation REG_F1", "UNLOAD, DEHAM"]),
    dict(x=260, y=190, w=170, h=170, style="accent", lines=["edge", "TLS 1.3, upgrade headers", "Authorization passes", "through unchanged", "proxy_buffering off", "on /events/"]),
    dict(x=490, y=90, w=200, h=70, style="box", lines=["admission, once", "signed in, may see ABC123", "then the stream starts"]),
    dict(x=490, y=190, w=200, h=70, style="ink", lines=["bo: error message,", "FORBIDDEN, no event follows", "(subscribers stay 0)"]),
    dict(x=490, y=410, w=200, h=70, style="box", lines=["handling store", "evt_10 stored, then", "broadcast to watchers"]),
    dict(x=490, y=290, w=200, h=70, style="box", lines=["feed: 401 / 403 / 200", "evt_9 resume replays", "evt_10, then live"]),
    dict(x=750, y=90, w=210, h=80, style="accent", lines=["next to ana, a fresh execution", "location Hamburg, IN_PORT", "registrationTime FORBIDDEN"]),
    dict(x=750, y=200, w=210, h=80, style="accent", lines=["next to ops, a fresh execution", "same selection, as ops:", "registrationTime is a value"]),
    dict(x=750, y=310, w=210, h=70, style="sub", lines=["frames of ana's run", "init, ack, subscribe,", "next, complete"]),
    dict(x=750, y=410, w=210, h=70, style="sub", lines=["TrackCargo ABC123", "then says IN_PORT"]),
]
edges = [
    dict(x1=200, y1=125, x2=260, y2=240, label="upgrade", lx=-14, ly=-8),
    dict(x1=200, y1=225, x2=260, y2=260),
    dict(x1=200, y1=325, x2=260, y2=300, dashed=True),
    dict(x1=200, y1=430, x2=300, y2=360, amber=True, label="mutation", lx=-20, ly=6),
    dict(x1=400, y1=360, x2=490, y2=435, amber=True, label="proxied", lx=40, ly=-4),
    dict(x1=430, y1=215, x2=490, y2=125),
    dict(x1=430, y1=235, x2=490, y2=225),
    dict(x1=430, y1=325, x2=490, y2=325, dashed=True),
    dict(x1=590, y1=410, x2=590, y2=360, amber=True, label="broadcast", lx=34, ly=0),
    dict(x1=690, y1=125, x2=750, y2=125),
    dict(x1=690, y1=410, x2=800, y2=280, amber=True),
    dict(x1=850, y1=170, x2=850, y2=200, dashed=True),
    dict(x1=850, y1=280, x2=850, y2=310, dashed=True),
    dict(x1=690, y1=445, x2=750, y2=445),
]
notes = [
    dict(x=500, y=28, text="Admission happens once; authorization of fields happens on every event, as the subscriber", anchor="middle", bold=True),
    dict(x=500, y=542, text="Values from verify.sh: evt_10 is the first write of the run on each public instance.", anchor="middle", size=12, color="#555555"),
]
g.emit("27-subscription-path", 1000, 565, bands=bands, nodes=nodes, edges=edges, notes=notes)
