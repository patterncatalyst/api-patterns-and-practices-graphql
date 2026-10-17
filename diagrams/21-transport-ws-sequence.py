"""Spec for assets/diagrams/21-transport-ws-sequence.{svg,excalidraw}. Regenerate: python3 -I diagrams/21-transport-ws-sequence.py

The frames of one graphql-transport-ws subscription, as the client logged them in
examples/21-real-time/verify.sh case 3 (both stacks exchange the same six frames):
connection_init, connection_ack, subscribe, next for evt_10, next for evt_12 and
the client's complete. The DEF456 registration (evt_11) produced no frame.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

L, R = 230, 770
bands = [dict(x=20, y=50, w=960, h=470, label="graphql-transport-ws: one subscription")]
nodes = [
    dict(x=L - 90, y=80, w=180, h=50, style="user", lines=["client", "gql WebsocketsTransport"]),
    dict(x=R - 90, y=80, w=180, h=50, style="box", lines=["server", "/graphql, subprotocol offered"]),
]
Y = [180, 232, 284, 342, 400, 458]
edges = [
    dict(x1=L, y1=130, x2=L, y2=500, dashed=True),
    dict(x1=R, y1=130, x2=R, y2=500, dashed=True),
    dict(x1=L, y1=Y[0], x2=R, y2=Y[0], label="connection_init  {}", lx=0, ly=-8),
    dict(x1=R, y1=Y[1], x2=L, y2=Y[1], label="connection_ack", lx=0, ly=-8),
    dict(x1=L, y1=Y[2], x2=R, y2=Y[2], label="subscribe  id 1, subscription Watch, trackingId ABC123", lx=0, ly=-8),
    dict(x1=R, y1=Y[3], x2=L, y2=Y[3], amber=True, label="next  id 1  evt_10, UNLOAD, Hamburg, IN_PORT", lx=0, ly=-8),
    dict(x1=R, y1=Y[4], x2=L, y2=Y[4], amber=True, label="next  id 1  evt_12, LOAD, Hamburg, ONBOARD_CARRIER", lx=0, ly=-8),
    dict(x1=L, y1=Y[5], x2=R, y2=Y[5], label="complete  id 1", lx=0, ly=-8),
]
notes = [
    dict(x=500, y=28, text="Six frames for a subscription that delivers two events", anchor="middle", bold=True),
    dict(x=790, y=Y[3] + 4, text="evt_10 registered", size=11, color="#555555"),
    dict(x=790, y=Y[4] + 4, text="evt_12 registered", size=11, color="#555555"),
    dict(x=40, y=Y[3] + 4, text="DEF456 event: no frame", size=11, color="#555555"),
    dict(x=500, y=506, text="The client sends complete after its second event; the server removes the subscriber.", anchor="middle", size=12, color="#555555"),
]
g.emit("21-transport-ws-sequence", 1000, 540, bands=bands, nodes=nodes, edges=edges, notes=notes)
