"""Spec for assets/diagrams/16-edge-cache-hit.{svg,excalidraw}. Regenerate: python3 -I diagrams/16-edge-cache-hit.py

Drawn from one run of examples/16-caching on the Quarkus stack (edge port 8262,
server port 8260): the PortName document, registered by POST, read by GET with
variables {"code":"USNYC"} and Accept: application/json. The first GET is a
MISS and the source-call log shows one location.getLocation:USNYC call; the
second is a HIT and the log is empty. The headers are the ones curl printed.
The Python stack (8263/8261) answers the same.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=1060, h=170, label="GET 1: nothing stored yet"),
    dict(x=20, y=240, w=1060, h=170, label="GET 2: the same URL, a moment later"),
]
nodes = [
    dict(x=45, y=88, w=220, h=100, style="user", lines=["GET /graphql", "?variables={code:USNYC}", "&extensions={sha256Hash}", "Accept: application/json"]),
    dict(x=315, y=88, w=220, h=100, style="accent", lines=["nginx :8262", "no entry for this URL", "X-Cache-Status: MISS", "stores the answer"]),
    dict(x=585, y=88, w=220, h=100, style="box", lines=["Quarkus :8260", "Cache-Control:", "public, max-age=300"]),
    dict(x=855, y=88, w=205, h=100, style="box", lines=["location owner", "location.getLocation:USNYC", "1 source call"]),
    dict(x=45, y=278, w=220, h=100, style="user", lines=["GET /graphql", "?variables={code:USNYC}", "&extensions={sha256Hash}", "Accept: application/json"]),
    dict(x=315, y=278, w=220, h=100, style="accent", lines=["nginx :8262", "entry found, fresh", "X-Cache-Status: HIT", "answers from the cache"]),
    dict(x=585, y=278, w=220, h=100, style="ghost", lines=["Quarkus :8260", "not reached"]),
    dict(x=855, y=278, w=205, h=100, style="ghost", lines=["location owner", "0 source calls"]),
]
edges = [
    dict(x1=265, y1=138, x2=315, y2=138),
    dict(x1=535, y1=138, x2=585, y2=138),
    dict(x1=805, y1=138, x2=855, y2=138),
    dict(x1=265, y1=328, x2=315, y2=328, amber=True),
]
notes = [
    dict(x=550, y=28, text="A persisted GET of reference data: stored by the first request, answered by the second", anchor="middle", bold=True),
    dict(x=550, y=436, text="The body of both responses is {\"data\":{\"location\":{\"name\":\"New York\"}}}. Quarkus and Python differ only in header case.", anchor="middle", size=12, color="#555555"),
]
g.emit("16-edge-cache-hit", 1100, 460, bands=bands, nodes=nodes, edges=edges, notes=notes)
