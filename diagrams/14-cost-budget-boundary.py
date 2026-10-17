"""Spec for assets/diagrams/14-cost-budget-boundary.{svg,excalidraw}. Regenerate: python3 -I diagrams/14-cost-budget-boundary.py

Q_EDGE(n): handlingHistory(first: n) under cargos(first: 50), cost 151 + 150 n.
The bars are the costs both stacks reported in a run with the budget set to 1
(301, 451, 601, 751, 901, 1051). verify.sh asserts the two on either side of
the budget of 1000 with the budget at its real value: n = 5 (901) runs and n = 6
(1051) is refused with "maximum query complexity exceeded 1051 > 1000".
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

BASE, SCALE = 440, 0.28
nodes, notes = [], []
for n in range(1, 7):
    cost = 151 + 150 * n
    height = round(cost * SCALE)
    x = 120 + (n - 1) * 140
    refused = cost > 1000
    nodes.append(dict(x=x, y=BASE - height, w=110, h=height, style="accent" if refused else "box", lines=[f"{cost:,}", "refused" if refused else "runs"]))
    notes.append(dict(x=x + 55, y=BASE + 24, text=f"first: {n}", anchor="middle", size=13, color="#1d1d1d"))
nodes.append(dict(x=100, y=BASE - round(1000 * SCALE), w=850, h=2, style="ink", lines=[""]))
notes += [
    dict(x=500, y=28, text="One page size decides whether the query is admitted", anchor="middle", bold=True),
    dict(x=104, y=BASE - round(1000 * SCALE) - 8, text="budget 1,000", size=13, color="#b8650a"),
    dict(x=500, y=BASE + 60, text="cost = 151 + 150 n for handlingHistory(first: n) under cargos(first: 50)", anchor="middle", size=12, color="#555555"),
    dict(x=500, y=BASE + 80, text="n = 5 costs 901 and runs; n = 6 costs 1,051 and is refused before any source call.", anchor="middle", size=12, color="#555555"),
]
g.emit("14-cost-budget-boundary", 1000, 540, nodes=nodes, notes=notes)
