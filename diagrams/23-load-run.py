"""Spec for assets/diagrams/23-load-run.{svg,excalidraw}. Regenerate: python3 -I diagrams/23-load-run.py

The `cost` load run of examples/23-testing/verify.sh, on either stack: two
scenarios start together, 4 virtual users sending 80 FanOut requests and 4
sending 80 OverBudget requests. The server prices FanOut at 53 and runs it; it
prices OverBudget at 7,651 against the budget of 1,000 and refuses it. The
source-call log then holds 80 request ids, each with 8 calls on Quarkus and 6 on
Python, and no call from a refused request.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=235, y=48, w=440, h=400, label="Server: quarkus or python")]
nodes = [
    dict(x=20, y=96, w=150, h=64, style="user", lines=["4 virtual users", "80 x FanOut"]),
    dict(x=20, y=340, w=150, h=64, style="user", lines=["4 virtual users", "80 x OverBudget"]),
    dict(x=255, y=96, w=170, h=64, style="box", lines=["Cost check", "cost 53, budget 1,000"]),
    dict(x=485, y=96, w=170, h=64, style="accent", lines=["Execution", "batched resolvers"]),
    dict(x=485, y=196, w=170, h=96, style="box", lines=["Bulk source calls", "booking.getCargos", "routing.getItineraries", "8 per request, 6 on Python"]),
    dict(x=255, y=340, w=170, h=64, style="box", lines=["Cost check", "cost 7,651, budget 1,000"]),
    dict(x=485, y=340, w=170, h=64, style="ink", lines=["Refused", "error, no data"]),
    dict(x=730, y=196, w=240, h=120, style="ink", lines=["Source-call log", "grouped by request id", "80 request ids, 8 or 6 calls each", "none from OverBudget"]),
]
edges = [
    dict(x1=170, y1=128, x2=255, y2=128, label="FanOut", lx=0, ly=-8),
    dict(x1=425, y1=128, x2=485, y2=128, label="runs", lx=0, ly=-8, amber=True),
    dict(x1=570, y1=160, x2=570, y2=196, amber=True),
    dict(x1=655, y1=244, x2=730, y2=244, label="logged", lx=0, ly=-8, amber=True),
    dict(x1=170, y1=372, x2=255, y2=372, label="OverBudget", lx=0, ly=-8),
    dict(x1=425, y1=372, x2=485, y2=372, label="over", lx=0, ly=-8),
    dict(x1=655, y1=372, x2=800, y2=316, dashed=True, label="no call", lx=34, ly=8),
]
notes = [
    dict(x=500, y=28, text="One load run: accepted requests fan out into calls, refused requests stop at the cost check", anchor="middle", bold=True),
    dict(x=500, y=474, text="160 requests in, 80 request ids in the log. Counts are exact on any machine; latency is printed and not asserted.", anchor="middle", size=12, color="#555555"),
]
g.emit("23-load-run", 1000, 490, bands=bands, nodes=nodes, edges=edges, notes=notes)
