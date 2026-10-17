"""Spec for examples/23-testing/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/23-testing-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "23-testing")
g.emit("architecture", 1000, 540,
 bands=[dict(x=20, y=20, w=960, h=500, label="examples/23-testing - compose stack (gql-ch23-testing)")],
 nodes=[
  dict(x=40, y=120, w=160, h=70, style="user", lines=["verify.sh", "curl, docker compose run"]),
  dict(x=300, y=60, w=270, h=100, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", ":8080 -> host :8330 /graphql", "/debug/source-calls (lab only)"]),
  dict(x=300, y=180, w=270, h=100, style="box", lines=["python", "Strawberry on FastAPI (code-first)", ":8080 -> host :8331 /graphql", "/debug/source-calls (lab only)"]),
  dict(x=300, y=330, w=270, h=70, style="ghost", lines=["quarkus-test", "profile test: mvn verify", "reports and schema to /out"]),
  dict(x=300, y=420, w=270, h=70, style="ghost", lines=["python-test", "profile test: pytest", "junit.xml and schema to /out"]),
  dict(x=40, y=340, w=190, h=80, style="ghost", lines=["load", "profile load: k6 2.3.0", "UBI 10 minimal"]),
  dict(x=700, y=70, w=250, h=80, style="accent", lines=["contracts/schema/", "canonical SDL", "diffed against both stacks"]),
  dict(x=700, y=360, w=250, h=90, style="accent", lines=["documents/", "Chapter 22's four operations", "FanOut, OverBudget, fixture"]),
 ],
 edges=[
  dict(x1=200, y1=140, x2=300, y2=110, label="POST /graphql", lx=-6, ly=-8),
  dict(x1=200, y1=170, x2=300, y2=225, label="the same documents", lx=-8, ly=16),
  dict(x1=230, y1=370, x2=300, y2=265, label="k6, one stack per run", amber=True, lx=-36, ly=14),
  dict(x1=570, y1=100, x2=700, y2=100, label="introspect + diff", amber=True, lx=0, ly=-8),
  dict(x1=570, y1=235, x2=700, y2=140, amber=True),
  dict(x1=700, y1=395, x2=570, y2=365, dashed=True),
  dict(x1=700, y1=420, x2=570, y2=455, dashed=True),
  dict(x1=700, y1=410, x2=230, y2=410, dashed=True, label="build context", lx=60, ly=-8),
  dict(x1=230, y1=345, x2=300, y2=150, amber=True),
 ],
 notes=[dict(x=50, y=508, text="verify.sh runs 22 Quarkus and 18 Python tests, then 160, 160, 40 and 120 load iterations on each stack.", size=12, color="#555555")])
