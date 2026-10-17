"""Spec for assets/diagrams/14-cost-accumulation.{svg,excalidraw}. Regenerate: python3 -I diagrams/14-cost-accumulation.py

The cost of Chapter 1's nested query (Q_CH1), computed bottom-up with the formula
cost = 1 + m * (sum of the children's costs). The root value, 385151, is the
message both stacks return in verify.sh; the chain beneath it is the arithmetic
(id 1, node 2, edges 3, handlingHistory 1 + 50 x 3 = 151, and so on). The side
panel is Q_FAN, priced 53 on both stacks in a run with the budget set to 1. The
bars at the foot are the costs of Q_FAN (53), Q_EDGE(5) (901), Q_WIDE_COST
(7651) and Q_CH1 (385151) on a log scale, against the budget of 1000.
"""
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

X = [20, 210, 400, 590]  # four columns, 150 wide
W, H = 150, 56
ROW = [66, 176, 286]


def box(col, row, field, cost, style="box"):
    return dict(x=X[col], y=ROW[row], w=W, h=H, style=style, lines=[field, (f"first: 50, cost {cost}" if style == "accent" else f"cost {cost}")])


nodes = [
    # row 1, left to right
    box(0, 0, "cargos", "385,151", "accent"),
    box(1, 0, "edges", "7,703"),
    box(2, 0, "node", "7,702"),
    box(3, 0, "handlingHistory", "7,701", "accent"),
    # row 2, right to left
    box(3, 1, "edges", "154"),
    box(2, 1, "node", "153"),
    box(1, 1, "cargo", "152"),
    box(0, 1, "handlingHistory", "151", "accent"),
    # row 3, left to right
    box(0, 2, "edges", "3"),
    box(1, 2, "node", "2"),
    box(2, 2, "id", "1"),
]
edges = [
    dict(x1=X[0] + W, y1=ROW[0] + 28, x2=X[1], y2=ROW[0] + 28, label="x 50", lx=0, ly=-8, amber=True),
    dict(x1=X[1] + W, y1=ROW[0] + 28, x2=X[2], y2=ROW[0] + 28),
    dict(x1=X[2] + W, y1=ROW[0] + 28, x2=X[3], y2=ROW[0] + 28),
    dict(x1=X[3] + W / 2, y1=ROW[0] + H, x2=X[3] + W / 2, y2=ROW[1], label="x 50", lx=24, ly=4, amber=True),
    dict(x1=X[3], y1=ROW[1] + 28, x2=X[2] + W, y2=ROW[1] + 28),
    dict(x1=X[2], y1=ROW[1] + 28, x2=X[1] + W, y2=ROW[1] + 28),
    dict(x1=X[1], y1=ROW[1] + 28, x2=X[0] + W, y2=ROW[1] + 28),
    dict(x1=X[0] + W / 2, y1=ROW[1] + H, x2=X[0] + W / 2, y2=ROW[2], label="x 50", lx=24, ly=4, amber=True),
    dict(x1=X[0] + W, y1=ROW[2] + 28, x2=X[1], y2=ROW[2] + 28),
    dict(x1=X[1] + W, y1=ROW[2] + 28, x2=X[2], y2=ROW[2] + 28),
]

# Side panel: Q_FAN by hand.
bands = [
    dict(x=752, y=50, w=228, h=300, label="Q_FAN by hand: 53"),
    dict(x=20, y=368, w=960, h=190, label="Cost on a log scale, against the budget"),
]
fan = [
    "trackingId = 1",
    "voyage { number } = 1 + 1 = 2",
    "load/unloadLocation = 2 each",
    "legs = 1 + (2 + 2 + 2) = 7",
    "itinerary = 1 + 7 = 8",
    "delivery { transportStatus } = 2",
    "node = 1 + (1 + 8 + 2) = 12",
    "edges = 1 + 12 = 13",
    "cargos(first: 4) = 1 + 4 x 13 = 53",
]
notes = [dict(x=766, y=96 + 27 * i, text=line, size=12, color="#1d1d1d") for i, line in enumerate(fan)]
notes.append(dict(x=766, y=96 + 27 * len(fan), text="legs has no page size: m = 1", size=12, color="#555555"))

# Log-scale bars.
LOGMAX = math.log10(400000)
BX, BW = 200, 700


def width(value):
    return round(BW * math.log10(value) / LOGMAX)


bars = [("Q_FAN", 53, "box"), ("Q_EDGE(5)", 901, "box"), ("Q_WIDE_COST", 7651, "accent"), ("Q_CH1", 385151, "accent")]
for i, (name, value, style) in enumerate(bars):
    y = 400 + i * 36
    nodes.append(dict(x=BX, y=y, w=width(value), h=28, style=style, lines=[f"{value:,}"]))
    notes.append(dict(x=30, y=y + 19, text=name, size=12, color="#1d1d1d"))
budget_x = BX + width(1000)
nodes.append(dict(x=budget_x, y=392, w=2, h=156, style="ink", lines=[""]))
notes.append(dict(x=budget_x + 8, y=558 - 4, text="budget 1,000", size=12, color="#b8650a"))
notes += [
    dict(x=500, y=28, text="Cost accumulates from the leaves, and every page size multiplies everything beneath it", anchor="middle", bold=True),
]
g.emit("14-cost-accumulation", 1000, 580, bands=bands, nodes=nodes, edges=edges, notes=notes)
