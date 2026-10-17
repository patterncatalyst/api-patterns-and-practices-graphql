"""Spec for assets/diagrams/12-offset-vs-keyset.{svg,excalidraw}. Regenerate: python3 -I diagrams/12-offset-vs-keyset.py

Drawn from one real run on both stacks (identical): DEF456's handlingHistory read
three at a time. Page 1 is [evt_9, evt_8, evt_7]. Then CUSTOMS NLRTM completing
2026-10-11T20:00:00Z is registered and becomes evt_10, which sorts between evt_8
and evt_7. The keyset lane is page 2 as the server returned it (after the cursor
of evt_7); the offset lane is what skipping three items would return now, taken
from the same run's full list. Cite: Kleppmann, Designing Data-Intensive
Applications, 2nd ed., on ordered index range scans.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

W, GAP, X0 = 100, 10, 190
bands = [
    dict(x=20, y=50, w=960, h=96, label="after the insert, newest first"),
    dict(x=20, y=170, w=960, h=130, label="offset: skip 3, take 3"),
    dict(x=20, y=320, w=960, h=130, label="keyset: after the cursor of evt_7, take 3"),
]
order = ["evt_9", "evt_8", "evt_10", "evt_7", "evt_6", "evt_5", "evt_4", "evt_3"]
times = {"evt_9": "10-12 15:00", "evt_8": "10-12 08:00", "evt_10": "10-11 20:00", "evt_7": "10-11 18:20",
         "evt_6": "10-10 06:15", "evt_5": "10-09 14:30", "evt_4": "10-01 08:15", "evt_3": "09-30 15:00"}


def x_of(i):
    return X0 + i * (W + GAP) - 80


nodes = []
for i, e in enumerate(order):
    style = "accent" if e == "evt_10" else "box"
    nodes.append(dict(x=x_of(i), y=84, w=W, h=50, style=style, lines=[e, times[e]]))
# offset lane: items 4-6 of the list as it is now
for i, e in enumerate(order[3:6]):
    nodes.append(dict(x=x_of(3 + i), y=206, w=W, h=50, style="accent" if e == "evt_7" else "box", lines=[e, times[e]]))
nodes.append(dict(x=x_of(0), y=206, w=3 * W + 2 * GAP, h=50, style="ghost", lines=["skipped: evt_9, evt_8, evt_10", "three items"]))
nodes.append(dict(x=x_of(3) + 0, y=262, w=W, h=28, style="sub", lines=["repeat"]))
for i, e in enumerate(order[4:7]):
    nodes.append(dict(x=x_of(4 + i), y=356, w=W, h=50, style="box", lines=[e, times[e]]))
nodes.append(dict(x=x_of(0), y=356, w=4 * W + 3 * GAP, h=50, style="ghost", lines=["seek past the key of evt_7", "no counting from the start"]))
edges = [dict(x1=x_of(3) + W / 2, y1=134, x2=x_of(3) + W / 2, y2=206, dashed=True, amber=True)]
notes = [
    dict(x=500, y=28, text="Offset counts rows from the start, so an insert above the page repeats an item; keyset seeks on the key", anchor="middle", bold=True),
    dict(x=500, y=478, text="Before the insert page 1 was evt_9, evt_8, evt_7 and page 2 was evt_6, evt_5, evt_4. Totals: 7 events, then 8.", anchor="middle", size=12, color="#555555"),
    dict(x=500, y=496, text="DDIA, 2nd ed.: a B-tree index is ordered, so a range scan starts at a key.", anchor="middle", size=12, color="#555555"),
]
g.emit("12-offset-vs-keyset", 1000, 515, bands=bands, nodes=nodes, edges=edges, notes=notes)
