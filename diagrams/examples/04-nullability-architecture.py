"""Spec for examples/04-nullability/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/04-nullability-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "04-nullability")
g.emit("architecture", 1000, 500,
 bands=[dict(x=20, y=20, w=960, h=460, label="examples/04-nullability - compose stack (gql-ch04-null)")],
 nodes=[
  dict(x=50, y=200, w=170, h=70, style="user", lines=["curl / GraphiQL", "client"]),
  dict(x=310, y=80, w=250, h=130, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "@Source resolvers over the voyage,", "location and delivery sources", "seed: 5 cargos, 3 with a fault", ":8080 -> host :8140 /graphql"]),
  dict(x=310, y=280, w=250, h=130, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "resolver methods over the voyage,", "location and delivery sources", "seed: 5 cargos, 3 with a fault", ":8080 -> host :8141 /graphql"]),
  dict(x=700, y=150, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
  dict(x=700, y=330, w=250, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=220, y1=225, x2=310, y2=150, label="selection", lx=-34, ly=-34),
  dict(x1=220, y1=245, x2=310, y2=340, label="selection", lx=-30, ly=26),
  dict(x1=310, y1=180, x2=220, y2=240, dashed=True),
  dict(x1=560, y1=130, x2=700, y2=180, label="introspect + diff", amber=True, lx=12, ly=-24),
  dict(x1=560, y1=350, x2=700, y2=235, label="introspect + diff", amber=True, lx=-40, ly=-28, elx=-90, ely=-14),
  dict(x1=560, y1=385, x2=700, y2=370, label="OTLP (both stacks)", dashed=True, lx=-6, ly=18),
 ],
 notes=[dict(x=50, y=455, text="A failing source nulls its field or the nearest nullable parent. verify.sh checks data and error path on each stack, then diffs each schema.", size=12, color="#555555")])
