"""Spec for examples/21-real-time/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/21-real-time-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "21-real-time")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/21-real-time - compose stack (gql-ch21-real-time)")],
 nodes=[
  dict(x=40, y=90, w=190, h=70, style="user", lines=["curl / verify.sh", "mutations, SSE, debug reads"]),
  dict(x=40, y=330, w=190, h=84, style="user", lines=["client (profile client)", "gql[websockets]", "client/subscribe.py"]),
  dict(x=300, y=70, w=300, h=150, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "@Subscription Multi, BroadcastProcessor", "ws: graphql-transport-ws, graphql-ws", "/events/cargos/{id} (Quarkus REST SSE)", ":8080 -> host :8310"]),
  dict(x=300, y=290, w=300, h=150, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "async generator over a bounded queue", "ws + graphql-sse on /graphql", "/events/cargos/{id} (EventSourceResponse)", ":8080 -> host :8311"]),
  dict(x=700, y=140, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(whole SDL, Subscription included)"]),
  dict(x=700, y=360, w=250, h=70, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=230, y1=115, x2=300, y2=120, label="HTTP, SSE (both stacks)", lx=14, ly=-12),
  dict(x1=230, y1=140, x2=300, y2=330),
  dict(x1=230, y1=360, x2=300, y2=160, label="ws://quarkus", lx=-20, ly=-30),
  dict(x1=230, y1=385, x2=300, y2=370, label="ws://python", lx=-10, ly=18),
  dict(x1=600, y1=130, x2=700, y2=170, label="introspect + diff", amber=True, lx=14, ly=-24),
  dict(x1=600, y1=350, x2=700, y2=225, label="introspect + diff", amber=True, lx=14, ly=44),
  dict(x1=600, y1=415, x2=700, y2=395, label="OTLP (both stacks)", dashed=True, lx=24, ly=-12),
 ],
 notes=[dict(x=50, y=515, text="verify.sh starts the client on the compose network, gates every mutation on /debug/subscribers, and reads the frames it logs.", size=12, color="#555555")])
