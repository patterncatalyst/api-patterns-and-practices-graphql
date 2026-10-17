"""Spec for assets/diagrams/08-idempotent-replay.{svg,excalidraw}. Regenerate: python3 -I diagrams/08-idempotent-replay.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X0, SCALE = 190, 0.5  # x of t=0, pixels per millisecond
# Schematic timing: each source call is 250 ms.


def bar(label, start, end, y, style, lines=None):
    return dict(x=round(X0 + start * SCALE), y=y, w=round((end - start) * SCALE), h=44, style=style, lines=lines or [label])


bands = [
    dict(x=20, y=50, w=1060, h=76, label="first request, key k-001"),
    dict(x=20, y=146, w=1060, h=76, label="retry after the lost response, key k-001"),
    dict(x=20, y=242, w=1060, h=76, label="retry without a key", fill="#ffffff"),
]
nodes = [
    bar("", 0, 250, 72, "box", ["lookup k-001", "miss"]),
    bar("", 250, 500, 72, "accent", ["appendEvent", "writes evt_3"]),
    bar("", 500, 900, 72, "ghost", ["response lost", "client times out"]),
    bar("", 1000, 1250, 168, "accent", ["lookup k-001", "hit: evt_3"]),
    bar("", 1250, 1500, 168, "box", ["re-read cargo", "returns evt_3"]),
    bar("", 1000, 1250, 264, "ghost", ["no lookup", "no key"]),
    bar("", 1250, 1500, 264, "ghost", ["appendEvent", "writes evt_4"]),
]
edges = [
    dict(x1=round(X0 + 900 * SCALE), y1=94, x2=round(X0 + 1000 * SCALE), y2=190, amber=True, label="retry", lx=26, ly=-6),
]
notes = [
    dict(x=540, y=28, text="The same retry, with and without an idempotency key", anchor="middle", bold=True),
    dict(x=round(X0 + 1500 * SCALE) + 14, y=194, text="store: evt_3 only", size=12, color="#b8650a"),
    dict(x=round(X0 + 1500 * SCALE) + 14, y=290, text="store: evt_3 and evt_4", size=12, color="#555555"),
    dict(x=540, y=346, text="The key turns a second write into a read. Without it, the store cannot tell a retry from a second event.", anchor="middle", size=12, color="#555555"),
    dict(x=540, y=366, text="Schematic: each source call is 250 ms. Chapter 8's verify.sh asserts the order of the calls, never their duration.", anchor="middle", size=12, color="#555555"),
]
g.emit("08-idempotent-replay", 1100, 390, bands=bands, nodes=nodes, edges=edges, notes=notes)
