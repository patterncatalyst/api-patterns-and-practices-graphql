"""Spec for assets/diagrams/19-one-endpoint-blind-spot.{svg,excalidraw}. Regenerate: python3 -I diagrams/19-one-endpoint-blind-spot.py

Drawn from the named operations verify.sh sends to one stack: FanOut once,
TrackCargo three times, TrackLiteral once, CargoPage once (it carries a
SERVICE_UNAVAILABLE error at GHI345's edge) and LegacyArrival three times (two
with X-Client-Name legacy-app). Nine requests; every response is HTTP 200. The
left panel is what telemetry keyed by URL and status sees; the right panel is
the same nine requests keyed by operation name, error code and field coordinate.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=440, h=380, label="Keyed by URL and status"),
    dict(x=540, y=50, w=440, h=380, label="Keyed by operation name, error code and field"),
]
nodes = [
    dict(x=40, y=100, w=400, h=70, style="box", lines=["POST /graphql", "9 requests, one route"]),
    dict(x=40, y=195, w=400, h=70, style="box", lines=["status 200", "9 of 9, including the request that carried an error"]),
    dict(x=40, y=290, w=400, h=70, style="box", lines=["one latency distribution", "the fan-out page and the single lookup share it"]),
    dict(x=560, y=100, w=190, h=50, style="accent", lines=["FanOut", "1 request"]),
    dict(x=560, y=160, w=190, h=50, style="accent", lines=["TrackCargo", "3 requests"]),
    dict(x=560, y=220, w=190, h=50, style="accent", lines=["TrackLiteral", "1 request"]),
    dict(x=560, y=280, w=190, h=50, style="accent", lines=["CargoPage", "1 request, 1 error"]),
    dict(x=560, y=340, w=190, h=50, style="accent", lines=["LegacyArrival", "3 requests"]),
    dict(x=770, y=280, w=190, h=50, style="ink", lines=["SERVICE_UNAVAILABLE", "error.code: 1"]),
    dict(x=770, y=340, w=190, h=50, style="ink", lines=["Itinerary.finalArrivalDate", "3 uses, 2 by legacy-app"]),
    dict(x=770, y=100, w=190, h=110, style="sub", lines=["latency per operation", "FanOut and TrackCargo", "each get their own curve"]),
]
edges = [
    dict(x1=460, y1=240, x2=540, y2=240, amber=True, label="split by name", lx=0, ly=-8),
    dict(x1=750, y1=305, x2=770, y2=305, dashed=True),
    dict(x1=750, y1=365, x2=770, y2=365, dashed=True),
]
notes = [
    dict(x=500, y=28, text="An HTTP dashboard sees one route; the operation name and the code are what tell requests apart", anchor="middle", bold=True),
    dict(x=500, y=455, text="Counts are the nine named requests verify.sh sends to one stack. HTTP status stays 200 whether a response carries errors or not (Chapter 9).", anchor="middle", size=12, color="#555555"),
]
g.emit("19-one-endpoint-blind-spot", 1000, 480, bands=bands, nodes=nodes, edges=edges, notes=notes)
