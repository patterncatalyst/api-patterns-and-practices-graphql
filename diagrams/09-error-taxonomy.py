"""Spec for assets/diagrams/09-error-taxonomy.{svg,excalidraw}. Regenerate: python3 -I diagrams/09-error-taxonomy.py

The HTTP tags are the statuses and media types verify.sh asserts on both stacks.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=45, w=1060, h=130, label="Request error: the engine rejects the document"),
    dict(x=20, y=190, w=1060, h=130, label="Execution error: a resolver fails"),
    dict(x=20, y=335, w=1060, h=130, label="Domain failure: the mutation refuses the input"),
]
nodes = []
for i, step in enumerate(("Parse", "Validate", "Coerce variables", "Select operation")):
    nodes.append(dict(x=50 + i * 150, y=90, w=130, h=56, style="box", lines=[step]))
nodes += [
    dict(x=670, y=80, w=390, h=80, style="accent", lines=["errors with locations, no path", "no data (Python: data null), no resolver ran", "draft: 4xx/5xx; both stacks answer 200"]),
    dict(x=50, y=235, w=190, h=56, style="box", lines=["Resolver runs"]),
    dict(x=290, y=222, w=160, h=38, style="sub", lines=["Exposed: allowlisted"]),
    dict(x=290, y=266, w=160, h=38, style="sub", lines=["Unexpected: masked"]),
    dict(x=670, y=225, w=390, h=80, style="accent", lines=["data plus errors with path", "the null lands at the nearest nullable ancestor", "draft: 294 (SHOULD); both stacks answer 200"]),
    dict(x=50, y=380, w=400, h=56, style="box", lines=["Mutation validates the input", "VOYAGE_REQUIRED, UNKNOWN_VOYAGE, ..."]),
    dict(x=670, y=370, w=390, h=80, style="accent", lines=["data with userErrors, no errors key", "the payload is an ordinary value", "200 on both stacks"]),
]
edges = [dict(x1=180 + i * 150, y1=118, x2=200 + i * 150, y2=118) for i in range(3)]
edges += [
    dict(x1=630, y1=118, x2=670, y2=118, amber=True),
    dict(x1=240, y1=263, x2=290, y2=241),
    dict(x1=240, y1=263, x2=290, y2=285),
    dict(x1=450, y1=241, x2=670, y2=260, amber=True),
    dict(x1=450, y1=285, x2=670, y2=275, amber=True),
    dict(x1=450, y1=408, x2=670, y2=410, amber=True),
]
notes = [
    dict(x=550, y=24, text="Three kinds of failure, three response shapes", anchor="middle", bold=True),
    dict(x=550, y=488, text="The current GraphQL-over-HTTP draft requires 4xx/5xx for a request error and asks for the same under application/json. Both stacks answer 200 (verify.sh).", anchor="middle", size=12, color="#555555"),
]
g.emit("09-error-taxonomy", 1100, 510, bands=bands, nodes=nodes, edges=edges, notes=notes)
