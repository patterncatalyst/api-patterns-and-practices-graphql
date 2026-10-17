"""Spec for assets/diagrams/22-normalized-cache-update.{svg,excalidraw}. Regenerate: python3 -I diagrams/22-normalized-cache-update.py

A data-movement figure drawn from the run of examples/22-client-integration/clients/js
(verify.sh asserts every value on both stacks): TrackCargo is request 1 and fills the
cache; TrackCargoBrief selects a subset and makes no request; the RegisterHandling
payload (cargo { id delivery { transportStatus } }) is request 2 and replaces
delivery.transportStatus ONBOARD_CARRIER with IN_PORT in the same Cargo entry.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=330, h=410, label="Operations (Apollo Client)"),
    dict(x=370, y=50, w=610, h=410, label="InMemoryCache, flattened by __typename and id"),
]
nodes = [
    dict(x=40, y=90, w=290, h=70, style="box", lines=["1  TrackCargo(ABC123)", "request 1 · ONBOARD_CARRIER"]),
    dict(x=40, y=205, w=290, h=70, style="accent", lines=["2  TrackCargoBrief(ABC123)", "a subset of 1 · 0 requests"]),
    dict(x=40, y=320, w=290, h=110, style="box", lines=["3  RegisterHandling", "UNLOAD at DEHAM on V100S", "request 2 · payload selects", "cargo { id delivery { transportStatus } }"]),
    dict(x=390, y=90, w=200, h=70, style="sub", lines=["ROOT_QUERY", 'cargo({"trackingId":"ABC123"})']),
    dict(x=640, y=90, w=320, h=150, style="accent", lines=["Cargo:cargo_ABC123", "trackingId: ABC123", "description: Palletized electronics", "delivery.routingStatus: ROUTED", "delivery.transportStatus:", "ONBOARD_CARRIER, then IN_PORT"]),
    dict(x=640, y=300, w=150, h=60, style="sub", lines=["Location:loc_USNYC", "New York"]),
    dict(x=810, y=300, w=150, h=60, style="sub", lines=["Location:loc_NLRTM", "Rotterdam"]),
    dict(x=390, y=380, w=240, h=60, style="ink", lines=["HandlingEvent:evt_10", "the payload's new event, id only"]),
]
edges = [
    dict(x1=330, y1=125, x2=390, y2=125, label="fills", amber=True, lx=0, ly=-8),
    dict(x1=590, y1=125, x2=640, y2=125, label="ref", lx=0, ly=-8),
    dict(x1=700, y1=240, x2=715, y2=300, label="origin", lx=-22, ly=0),
    dict(x1=900, y1=240, x2=885, y2=300, label="destination", lx=34, ly=0),
    dict(x1=330, y1=250, x2=640, y2=215, label="answered from the entry", dashed=True, lx=0, ly=-12),
    dict(x1=330, y1=345, x2=640, y2=232, label="merges delivery", amber=True, lx=30, ly=34),
    dict(x1=330, y1=410, x2=390, y2=410, label="adds", lx=0, ly=-8),
]
notes = [
    dict(x=500, y=28, text="Two requests, three operations: the cache answers the second and takes the third", anchor="middle", bold=True),
    dict(x=40, y=482, text="delivery has no id, so its stored object is merged field by field (a typePolicy), and routingStatus survives a payload that selects only transportStatus.", size=12, color="#555555"),
]
g.emit("22-normalized-cache-update", 1000, 500, bands=bands, nodes=nodes, edges=edges, notes=notes)
