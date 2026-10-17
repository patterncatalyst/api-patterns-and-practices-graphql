"""Spec for assets/diagrams/06-serial-mutation.{svg,excalidraw}. Regenerate: python3 -I diagrams/06-serial-mutation.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X0, SCALE = 200, 0.6  # x of t=0, pixels per millisecond
# Schematic timing: each step is one 250 ms source call.


def bar(label, start, end, y, style):
    return dict(x=round(X0 + start * SCALE), y=y, w=round((end - start) * SCALE), h=34, style=style, lines=[label])


bands = [
    dict(x=20, y=50, w=860, h=58, label="a: registerHandlingEvent"),
    dict(x=20, y=130, w=860, h=58, label="b: registerHandlingEvent"),
    dict(x=20, y=224, w=860, h=58, label="if a and b were query fields", fill="#ffffff"),
]
nodes = [
    bar("append event", 0, 250, 62, "accent"),
    bar("payload re-read", 250, 500, 62, "box"),
    bar("append event", 500, 750, 142, "accent"),
    bar("payload re-read", 750, 1000, 142, "box"),
    bar("a", 0, 500, 236, "ghost"),
    bar("b", 0, 500, 262 - 0, "ghost"),
    dict(x=round(X0 + 500 * SCALE), y=44, w=1, h=150, style="sub", lines=[""]),
]
# The ghost lane holds two bars; give each its own row inside the band.
nodes[4] = dict(nodes[4], y=228, h=24)
nodes[5] = dict(nodes[5], y=254, h=24)
edges = [
    dict(x1=round(X0 + 500 * SCALE), y1=110, x2=round(X0 + 500 * SCALE), y2=128, amber=True),
]
notes = [
    dict(x=450, y=28, text="Top-level mutation fields run serially: b starts only after a, payload included, is complete", anchor="middle", bold=True),
    dict(x=round(X0 + 500 * SCALE) + 22, y=124, text="a is finished", size=11, color="#b8650a"),
    dict(x=450, y=318, text="Schematic: each step is one 250 ms source call. Chapter 8 measures this on the running stacks.", anchor="middle", size=12, color="#555555"),
]
g.emit("06-serial-mutation", 900, 340, bands=bands, nodes=nodes, edges=edges, notes=notes)
