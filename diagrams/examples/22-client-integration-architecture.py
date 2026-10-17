"""Spec for examples/22-client-integration/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/22-client-integration-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "22-client-integration")
g.emit("architecture", 1000, 540,
 bands=[
  dict(x=20, y=20, w=960, h=500, label="examples/22-client-integration - compose stack (gql-ch22-clients)"),
  dict(x=620, y=50, w=340, h=340, label="servers (each client runs against each)"),
 ],
 nodes=[
  dict(x=40, y=215, w=170, h=90, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "build context: schema"]),
  dict(x=300, y=60, w=190, h=70, style="user", lines=["js-client", "Apollo Client 4, Node 24", "no port"]),
  dict(x=300, y=170, w=190, h=70, style="user", lines=["python-client", "gql 4.4.0, httpx", "no port"]),
  dict(x=300, y=280, w=190, h=70, style="user", lines=["java-client", "SmallRye typesafe + dynamic", "no port"]),
  dict(x=300, y=390, w=190, h=70, style="ghost", lines=["codegen-check", "build stage of js-client", "no port"]),
  dict(x=650, y=90, w=280, h=110, style="box", lines=["quarkus", "SmallRye GraphQL", "the Chapter 13 tracking view", ":8080 -> host :8320 /graphql"]),
  dict(x=650, y=240, w=280, h=110, style="box", lines=["python", "Strawberry on FastAPI", "the Chapter 13 tracking view", ":8080 -> host :8321 /graphql"]),
 ],
 edges=[
  dict(x1=210, y1=245, x2=300, y2=100, amber=True, dashed=True, label="schema at image build", lx=-30, ly=-30),
  dict(x1=210, y1=260, x2=300, y2=205, amber=True, dashed=True),
  dict(x1=210, y1=285, x2=300, y2=425, amber=True, dashed=True),
  dict(x1=490, y1=95, x2=620, y2=150, label="POST /graphql", lx=0, ly=-12),
  dict(x1=490, y1=205, x2=620, y2=205, label="POST /graphql", lx=0, ly=-8),
  dict(x1=490, y1=315, x2=620, y2=260, label="POST /graphql", lx=0, ly=18),
 ],
 notes=[dict(x=40, y=500, text="Clients run on demand through compose_run; the servers are the ones from Chapter 13, unchanged apart from names and ports.", size=12, color="#555555")])
