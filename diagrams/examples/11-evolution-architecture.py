"""Spec for examples/11-evolution/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/11-evolution-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "11-evolution")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/11-evolution - compose stack (gql-ch11-evolution)")],
 nodes=[
  dict(x=50, y=150, w=170, h=70, style="user", lines=["curl / verify.sh", "client"]),
  dict(x=300, y=60, w=270, h=140, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "finalArrivalTime + deprecated finalArrivalDate", "5 sources, 250 ms each, each call logged", "/debug/source-calls (lab only)", ":8080 -> host :8210 /graphql"]),
  dict(x=300, y=240, w=270, h=140, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "finalArrivalTime + deprecated finalArrivalDate", "5 sources, 250 ms each, each call logged", "/debug/source-calls (lab only)", ":8080 -> host :8211 /graphql"]),
  dict(x=700, y=100, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
  dict(x=700, y=250, w=250, h=100, style="accent", lines=["gate fixtures", "copies of the SDL with one edit", "(temporary, in verify.sh)"]),
  dict(x=700, y=400, w=250, h=70, style="box", lines=["contracts/scripts/breaking.sh", "graphql-inspector diff"]),
  dict(x=300, y=440, w=270, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=220, y1=170, x2=300, y2=120, label="query, introspection", lx=-30, ly=-22),
  dict(x1=220, y1=200, x2=300, y2=290, label="query, introspection", lx=-30, ly=26),
  dict(x1=570, y1=100, x2=700, y2=130, label="introspect + diff", amber=True, lx=14, ly=-18),
  dict(x1=570, y1=330, x2=700, y2=180, label="introspect + diff", amber=True, lx=22, ly=30),
  dict(x1=825, y1=200, x2=825, y2=250, label="copy + one edit", lx=60, ly=0),
  dict(x1=825, y1=350, x2=825, y2=400, label="base vs new", amber=True, lx=50, ly=0),
  dict(x1=435, y1=380, x2=435, y2=440, label="OTLP (both stacks)", dashed=True, lx=62, ly=0),
 ],
 notes=[dict(x=50, y=516, text="verify.sh checks the deprecation on both stacks, then runs the breaking gate once on fixtures, not per stack.", size=12, color="#555555")])
