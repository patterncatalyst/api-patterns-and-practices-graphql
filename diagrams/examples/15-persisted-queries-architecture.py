"""Spec for examples/15-persisted-queries/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/15-persisted-queries-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "15-persisted-queries")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/15-persisted-queries - compose stack (gql-ch15-persisted)")],
 nodes=[
  dict(x=40, y=240, w=150, h=70, style="user", lines=["curl / verify.sh", "client"]),
  dict(x=260, y=70, w=260, h=110, style="box", lines=["quarkus  (apq)", "Vert.x route -> SmallRye GraphQL", "quarkus-cache, 1000 documents", ":8250 /graphql"]),
  dict(x=260, y=200, w=260, h=100, style="accent", lines=["quarkus-trusted", "same image, manifest only", ":8252 /graphql"]),
  dict(x=260, y=330, w=260, h=110, style="box", lines=["python  (apq)", "SchemaExtension -> Strawberry", "cachetools LRUCache, 1000 documents", ":8251 /graphql"]),
  dict(x=260, y=455, w=260, h=70, style="accent", lines=["python-trusted", "same image, manifest only", ":8253 /graphql"]),
  dict(x=700, y=200, w=250, h=100, style="accent", lines=["persisted-documents.json", "(Apollo manifest, mounted :ro,z", "into the two trusted services)"]),
  dict(x=700, y=70, w=250, h=70, style="box", lines=["contracts/schema/", "shipping/*.graphql (canonical SDL)"]),
  dict(x=700, y=455, w=250, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=190, y1=262, x2=260, y2=125, label="hash, text", lx=-18, ly=-26),
  dict(x1=190, y1=270, x2=260, y2=250),
  dict(x1=190, y1=285, x2=260, y2=385),
  dict(x1=190, y1=300, x2=260, y2=490),
  dict(x1=520, y1=250, x2=700, y2=250, label="reads at start", amber=True, lx=-6, ly=-14),
  dict(x1=520, y1=110, x2=700, y2=105, label="introspect + diff", amber=True, lx=0, ly=-12),
  dict(x1=520, y1=490, x2=700, y2=290, label="reads at start", amber=True, lx=30, ly=40),
  dict(x1=520, y1=385, x2=700, y2=130, label="introspect + diff", amber=True, lx=-40, ly=-120),
 ],
 notes=[dict(x=40, y=538, text="The trusted pair refuses introspection, so the contract checks run against the apq pair.", size=12, color="#555555")])
