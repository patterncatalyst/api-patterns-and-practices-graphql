"""Spec for assets/diagrams/21-three-ways-to-push.{svg,excalidraw}. Regenerate: python3 -I diagrams/21-three-ways-to-push.py

A comparison of the four ways a server can push to a client, by the properties
that decide between them. The first three columns are served by
examples/21-real-time/ (the Strawberry stack serves GraphQL over SSE; both stacks
serve the other two); the fourth is design guidance only.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

COLS = [
    ("GraphQL over WebSocket", "graphql-transport-ws"),
    ("GraphQL over SSE", "graphql-sse"),
    ("Plain SSE feed", "GET /events/cargos/{id}"),
    ("Raw WebSocket", "your own protocol"),
]
ROWS = [
    ("Direction", ["both ways on one socket", "server to client", "server to client", "both ways on one socket"]),
    ("Framing", ["JSON frames: next, complete", "SSE events: next, complete", "SSE events: handled", "yours to design"]),
    ("Selection", ["the client's selection set", "the client's selection set", "a fixed payload", "fixed by your protocol"]),
    ("Resume", ["none: subscribe again", "none: subscribe again", "Last-Event-ID replay", "yours to design"]),
    ("HTTP path", ["proxy must pass Upgrade", "an ordinary HTTP response", "an ordinary HTTP response", "proxy must pass Upgrade"]),
    ("Credentials", ["connection_init payload", "request headers", "request headers", "yours to design"]),
    ("Served here", ["Quarkus and Python", "Python", "Quarkus and Python", "prose only"]),
]

X0, CW, PAD = 150, 212, 10
bands = [dict(x=20, y=50, w=1000, h=490, label="One cargo, four ways to hear about the next handling event")]
nodes, notes = [], []
for c, (title, sub) in enumerate(COLS):
    style = "ghost" if c == 3 else "accent"
    nodes.append(dict(x=X0 + c * (CW + PAD), y=82, w=CW, h=52, style=style, lines=[title, sub]))
for r, (label, cells) in enumerate(ROWS):
    y = 148 + r * 54
    notes.append(dict(x=34, y=y + 29, text=label, size=12.5, bold=True))
    for c, text in enumerate(cells):
        style = "ghost" if c == 3 else ("accent" if r == 6 else "box")
        nodes.append(dict(x=X0 + c * (CW + PAD), y=y, w=CW, h=46, style=style, lines=[text]))
notes.append(dict(x=520, y=28, text="Push is a choice of transport, then of contract", anchor="middle", bold=True))
notes.append(dict(x=520, y=562, text="The GraphQL columns keep the selection set and the schema. The feed gives them up and gains HTTP semantics and resume.", anchor="middle", size=12, color="#555555"))
g.emit("21-three-ways-to-push", 1040, 590, bands=bands, nodes=nodes, notes=notes)
