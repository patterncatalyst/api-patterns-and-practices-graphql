"""Spec for examples/05-contract-first/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/05-contract-first-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "05-contract-first")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/05-contract-first - compose stack (gql-ch05-contract)")],
 nodes=[
  dict(x=40, y=215, w=150, h=70, style="user", lines=["verify.sh", "host script"]),
  dict(x=250, y=70, w=250, h=110, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "GET /graphql/schema.graphql", ":8080 -> host :8150"]),
  dict(x=250, y=320, w=250, h=110, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "strawberry export-schema", ":8080 -> host :8151"]),
  dict(x=570, y=195, w=170, h=110, style="accent", lines=["exported SDL", "quarkus.graphql", "python.graphql", "(temp dir)"]),
  dict(x=790, y=70, w=170, h=100, style="box", lines=["contracts/schema/", "canonical SDL", "npm run lint"]),
  dict(x=790, y=330, w=170, h=100, style="ghost", lines=["seeded drift", "5 sed edits per export", "each must fail"]),
 ],
 edges=[
  dict(x1=190, y1=240, x2=250, y2=140, label="HTTP GET", lx=-36, ly=-4),
  dict(x1=190, y1=262, x2=250, y2=370, label="compose exec", lx=-40, ly=14),
  dict(x1=500, y1=140, x2=570, y2=235, amber=True),
  dict(x1=500, y1=370, x2=570, y2=270, amber=True),
  dict(x1=740, y1=225, x2=790, y2=135, amber=True, label="diff both ways", lx=76, ly=16),
  dict(x1=740, y1=275, x2=790, y2=360, dashed=True, label="copy + edit", lx=-40, ly=16),
 ],
 notes=[dict(x=50, y=475, text="Each stack exports the schema it builds; the exports are diffed against the contract and against each other.", size=12, color="#555555")])
