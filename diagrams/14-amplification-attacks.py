"""Spec for assets/diagrams/14-amplification-attacks.{svg,excalidraw}. Regenerate: python3 -I diagrams/14-amplification-attacks.py

Five requests that ask for too much, each with the size of its text and the work
it would cause. The sizes are the byte lengths of the queries in
examples/14-query-cost/verify.sh (D_DEEP 231, A_BOMB 16,093,
first: 5000 57, T_FLOOD 66,003, B_ARRAY 55). The costs and messages are the ones
verify.sh asserts on both stacks.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

PANELS = [
    ("Deep nesting", ["D_DEEP: 231 bytes", "16 fields deep, first: 1 throughout"],
     ["Cost 16", "depth grows with the text, not the data"],
     ["Quarkus: depth exceeded 16 > 15", "Python: operation depth of 14"], "accent"),
    ("Aliases", ["A_BOMB: 16,093 bytes", "150 aliases of one 7-field lookup"],
     ["150 lookups in one request", "each alias runs its own lookup"],
     ["Both: 150 aliases found", "Allowed: 20"], "accent"),
    ("Huge page", ["first: 5000: 57 bytes", "one cargos selection"],
     ["Cost 15,001", "and 5,000 rows to assemble"],
     ["Both: cost 15001 > 1000", "first: 51 reaches the page cap"], "accent"),
    ("Token flood", ["T_FLOOD: 66,003 bytes", "6,002 tokens of __typename"],
     ["Parser and validator work", "no resolver runs"],
     ["Quarkus: Unparseable input document", "Python: more than 5000 tokens"], "accent"),
    ("Batch array", ["B_ARRAY: 55 bytes", "two operations in one body"],
     ["Every operation costs what it costs", "N operations, one HTTP request"],
     ["Quarkus: 200, Unparseable request", "Python: 400, batching not enabled"], "accent"),
]

bands, nodes = [], []
for i, (title, request, work, caught, style) in enumerate(PANELS):
    x = 20 + (i % 3) * 325
    y = 50 + (i // 3) * 255
    bands.append(dict(x=x, y=y, w=310, h=240, label=title))
    nodes.append(dict(x=x + 12, y=y + 32, w=286, h=62, style="user", lines=request))
    nodes.append(dict(x=x + 12, y=y + 104, w=286, h=56, style="box", lines=["Work"] + work))
    nodes.append(dict(x=x + 12, y=y + 170, w=286, h=60, style=style, lines=["Caught by"] + caught))
notes = [
    dict(x=500, y=28, text="Five requests, each small next to the work it asks for", anchor="middle", bold=True),
    dict(x=500, y=568, text="Every refused request makes 0 source calls. Sizes are the text of the query; costs use the formula of this chapter.", anchor="middle", size=12, color="#555555"),
]
g.emit("14-amplification-attacks", 1000, 590, bands=bands, nodes=nodes, notes=notes)
