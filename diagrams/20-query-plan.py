"""Spec for assets/diagrams/20-query-plan.{svg,excalidraw}. Regenerate: python3 -I diagrams/20-query-plan.py

Drawn from one run of examples/20-federation/verify.sh: TrackCargo for ABC123
through gateway-a. The subgraph requests and their source calls are the ones the
subgraphs' /debug/source-calls logs hold after that one request: the cargo subgraph
saw two distinct requests, the handling subgraph one.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=400, label="One client request, three subgraph fetches")]
nodes = [
    dict(x=40, y=215, w=150, h=80, style="user", lines=["gateway", "TrackCargo(ABC123)", "one request"]),
    dict(x=250, y=80, w=220, h=90, style="box", lines=["1. cargo subgraph", "cargo, description, itinerary,", "legs { loadLocation { name } }"]),
    dict(x=250, y=190, w=220, h=90, style="accent", lines=["2. handling subgraph", "_entities(Cargo): delivery,", "handlingHistory(first: 2)"]),
    dict(x=250, y=300, w=220, h=90, style="box", lines=["3. cargo subgraph", "_entities(Location):", "name of each location handling named"]),
    dict(x=540, y=80, w=420, h=90, style="sub", lines=["booking.getCargo:ABC123", "routing.getItineraries:ABC123", "location.getLocations:DEHAM+USNYC"]),
    dict(x=540, y=190, w=420, h=90, style="sub", lines=["booking.getCargos:ABC123, routing.getItineraries:ABC123", "handling.pageEvents:ABC123", "handling.listEventsFor:ABC123"]),
    dict(x=540, y=300, w=420, h=90, style="sub", lines=["location.getLocations:USNYC", "one bulk call, however many references"]),
]
edges = [
    dict(x1=190, y1=240, x2=250, y2=135),
    dict(x1=190, y1=255, x2=250, y2=235, amber=True),
    dict(x1=190, y1=270, x2=250, y2=345),
    dict(x1=470, y1=125, x2=540, y2=125, dashed=True),
    dict(x1=470, y1=235, x2=540, y2=235, dashed=True),
    dict(x1=470, y1=345, x2=540, y2=345, dashed=True),
]
notes = [
    dict(x=500, y=28, text="The cargo subgraph is asked twice, the handling subgraph once", anchor="middle", bold=True),
    dict(x=40, y=425, text="Fetch 3 waits for fetch 2: only handling knows which locations the events and the delivery name.", size=12, color="#555555"),
    dict(x=40, y=442, text="Distinct request ids in the source-call logs: cargo 2, handling 1.", size=12, color="#555555"),
]
g.emit("20-query-plan", 1000, 470, bands=bands, nodes=nodes, edges=edges, notes=notes)
