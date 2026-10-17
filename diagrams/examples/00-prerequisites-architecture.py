"""Spec for examples/00-prerequisites/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/00-prerequisites-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "00-prerequisites")
g.emit("architecture", 980, 460,
 bands=[dict(x=20,y=20,w=940,h=420,label="examples/00-prerequisites - compose stack (gql-ch00-prereq)")],
 nodes=[
  dict(x=50,y=180,w=170,h=70,style="user",lines=["curl / GraphiQL","client"]),
  dict(x=300,y=90,w=230,h=100,style="box",lines=["quarkus","SmallRye GraphQL (code-first)","Query.cargo -> canned ABC123",":8080 -> host :8080 /graphql"]),
  dict(x=300,y=260,w=230,h=100,style="box",lines=["python","Strawberry on FastAPI (code-first)","Query.cargo -> canned ABC123",":8080 -> host :8081 /graphql"]),
  dict(x=650,y=165,w=270,h=100,style="accent",lines=["contracts/schema/","shipping/*.graphql","(canonical SDL, single source)"]),
  dict(x=650,y=330,w=270,h=60,style="ghost",lines=["otel-lgtm","(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=220,y1=205,x2=300,y2=140,label="cargo(trackingId)",lx=-48,ly=-16),
  dict(x1=220,y1=225,x2=300,y2=300,label="cargo(trackingId)",lx=-48,ly=26),
  dict(x1=530,y1=150,x2=650,y2=200,label="introspect + diff",amber=True,lx=12,ly=-28),
  dict(x1=530,y1=300,x2=650,y2=240,label="introspect + diff",amber=True,lx=-10,ly=48),
  dict(x1=530,y1=180,x2=650,y2=340,dashed=True),
  dict(x1=530,y1=345,x2=650,y2=360,label="OTLP (both stacks)",dashed=True,lx=-10,ly=24),
 ],
 notes=[dict(x=50,y=415,text="Two code-first servers, one canonical SDL: verify.sh checks the canned values on each stack, then diffs its live schema against the contract.",size=12,color="#555555")])
