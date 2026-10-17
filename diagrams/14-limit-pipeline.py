"""Spec for assets/diagrams/14-limit-pipeline.{svg,excalidraw}. Regenerate: python3 -I diagrams/14-limit-pipeline.py

Where each limit of examples/14-query-cost fires, drawn from the refusals
verify.sh asserts: a batch array at the HTTP layer, the 5,000-token limit in the
parser (T_FLOOD), depth and aliases in validation on Strawberry, depth, aliases and
cost before execution on SmallRye, cost before execution on Strawberry, and the page
cap in the resolver (first: 51). Every refusal leaves the source-call log empty.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

COL = [30 + i * 160 for i in range(6)]
W = 140
STAGES = ["HTTP body", "Parse", "Validate", "Before execute", "Resolve", "Sources"]

bands = [
    dict(x=20, y=90, w=960, h=200, label="SmallRye GraphQL on graphql-java"),
    dict(x=20, y=305, w=960, h=215, label="Strawberry on graphql-core"),
]
nodes = [dict(x=COL[i], y=48, w=W, h=30, style="ink", lines=[name]) for i, name in enumerate(STAGES)]
edges = []

# SmallRye lane: path at y=160
nodes += [
    dict(x=COL[0], y=128, w=W, h=64, style="accent", lines=["One JSON object", "an array is refused"]),
    dict(x=COL[1], y=128, w=W, h=64, style="accent", lines=["5,000 tokens", "ParserOptions"]),
    dict(x=COL[2], y=128, w=W, h=64, style="box", lines=["Standard rules", "no limit of ours"]),
    dict(x=COL[3], y=102, w=W, h=38, style="accent", lines=["Depth 15", "query-depth"]),
    dict(x=COL[3], y=144, w=W, h=38, style="accent", lines=["Aliases 20", "QueryCost"]),
    dict(x=COL[3], y=186, w=W, h=38, style="accent", lines=["Cost 1000", "QueryCost"]),
    dict(x=COL[4], y=128, w=W, h=64, style="accent", lines=["Page cap", "first 0..50"]),
    dict(x=COL[5], y=128, w=W, h=64, style="ink", lines=["Source calls", "admitted only"]),
    dict(x=COL[0], y=242, w=COL[4] + W - COL[0], h=36, style="ghost", lines=["Refused: HTTP 200, errors, no data, 0 source calls"]),
]
for i in range(5):
    edges.append(dict(x1=COL[i] + W, y1=160, x2=COL[i + 1], y2=160))
for i in (0, 1, 3):
    edges.append(dict(x1=COL[i] + W / 2, y1=192 if i != 3 else 224, x2=COL[i] + W / 2, y2=242, amber=True, dashed=True))
edges.append(dict(x1=COL[4] + W / 2, y1=192, x2=COL[4] + W / 2, y2=242, amber=True, dashed=True))

# Strawberry lane: path at y=380
nodes += [
    dict(x=COL[0], y=348, w=W, h=64, style="accent", lines=["Batching off", "an array: 400"]),
    dict(x=COL[1], y=348, w=W, h=64, style="accent", lines=["5,000 tokens", "MaxTokensLimiter"]),
    dict(x=COL[2], y=324, w=W, h=44, style="accent", lines=["Depth 14", "QueryDepthLimiter"]),
    dict(x=COL[2], y=372, w=W, h=44, style="accent", lines=["Aliases 20", "MaxAliasesLimiter"]),
    dict(x=COL[3], y=348, w=W, h=64, style="accent", lines=["Cost 1000", "QueryCostLimiter"]),
    dict(x=COL[4], y=348, w=W, h=64, style="accent", lines=["Page cap", "first 0..50"]),
    dict(x=COL[5], y=348, w=W, h=64, style="ink", lines=["Source calls", "admitted only"]),
    dict(x=COL[0], y=462, w=COL[4] + W - COL[0], h=36, style="ghost", lines=["Refused: HTTP 200 (400 for an array), errors, no data, 0 source calls"]),
]
for i in range(5):
    edges.append(dict(x1=COL[i] + W, y1=380, x2=COL[i + 1], y2=380 if i != 1 else 360))
for i, ybot in ((0, 412), (1, 412), (2, 416), (3, 412), (4, 412)):
    edges.append(dict(x1=COL[i] + W / 2, y1=ybot, x2=COL[i] + W / 2, y2=462, amber=True, dashed=True))

notes = [
    dict(x=500, y=28, text="A request meets each limit in order, and a refusal ends before any source call", anchor="middle", bold=True),
    dict(x=500, y=546, text="Depth counts a root field as 1 in graphql-java and 0 in Strawberry, so 15 and 14 refuse the same non-introspection documents.", anchor="middle", size=12, color="#555555"),
]
g.emit("14-limit-pipeline", 1000, 570, bands=bands, nodes=nodes, edges=edges, notes=notes)
