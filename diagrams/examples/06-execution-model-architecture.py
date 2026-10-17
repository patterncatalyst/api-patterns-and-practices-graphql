"""Spec for examples/06-execution-model/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/06-execution-model-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "06-execution-model")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/06-execution-model - compose stack (gql-ch06-exec)")],
 nodes=[
  dict(x=50, y=210, w=170, h=70, style="user", lines=["curl / verify.sh", "client"]),
  dict(x=300, y=70, w=270, h=140, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "resolvers return Uni (Mutiny)", "5 sources, 250 ms each, each call logged", "/debug/source-calls (lab only)", ":8080 -> host :8160 /graphql"]),
  dict(x=300, y=290, w=270, h=140, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "resolvers are async def", "5 sources, 250 ms each, each call logged", "/debug/source-calls (lab only)", ":8080 -> host :8161 /graphql"]),
  dict(x=700, y=150, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
  dict(x=700, y=350, w=250, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=220, y1=235, x2=300, y2=150, label="query", lx=-26, ly=-30),
  dict(x1=220, y1=255, x2=300, y2=350, label="query", lx=-26, ly=30),
  dict(x1=300, y1=190, x2=220, y2=245, dashed=True),
  dict(x1=570, y1=120, x2=700, y2=180, label="introspect + diff", amber=True, lx=14, ly=-24),
  dict(x1=570, y1=340, x2=700, y2=235, label="introspect + diff", amber=True, lx=14, ly=44),
  dict(x1=570, y1=395, x2=700, y2=380, label="OTLP (both stacks)", dashed=True, lx=-6, ly=18),
 ],
 notes=[dict(x=50, y=478, text="verify.sh reads each stack's source-call log after every query and asserts order and overlap, never duration.", size=12, color="#555555")])
