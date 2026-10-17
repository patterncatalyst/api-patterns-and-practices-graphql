"""Spec for examples/24-debugging/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/24-debugging-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "24-debugging")
g.emit("architecture", 1000, 600,
 bands=[dict(x=20, y=20, w=960, h=560, label="examples/24-debugging - compose stack (gql-ch24-debugging)")],
 nodes=[
  dict(x=40, y=250, w=160, h=70, style="user", lines=["curl / verify.sh", "client + traceparent"]),
  dict(x=280, y=60, w=250, h=100, style="box", lines=["quarkus (production)", "fast-jar, SmallRye GraphQL", ":8080 -> host :8340 /graphql"]),
  dict(x=280, y=180, w=250, h=100, style="accent", lines=["quarkus-dev (development)", "mvn quarkus:dev", "GraphQL UI, Dev UI", ":8080 -> host :8342"]),
  dict(x=280, y=300, w=250, h=100, style="box", lines=["python (profile prod)", "Strawberry on FastAPI", ":8080 -> host :8341 /graphql"]),
  dict(x=280, y=420, w=250, h=100, style="accent", lines=["python-dev (profile dev)", "the same image, GraphiQL", ":8080 -> host :8343 /graphql"]),
  dict(x=700, y=60, w=250, h=360, style="accent", lines=["lgtm (otel-lgtm 0.37.0)", "Collector, Tempo, Prometheus,", "Loki, Grafana", "Grafana 8344, Tempo 8345,", "Prometheus 8346, Loki 8347"]),
  dict(x=700, y=460, w=250, h=80, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
 ],
 edges=[
  dict(x1=200, y1=275, x2=280, y2=110, label="F1, F2", lx=-18, ly=-30),
  dict(x1=200, y1=280, x2=280, y2=230, label="F1, F2", lx=-14, ly=-12),
  dict(x1=200, y1=290, x2=280, y2=350, label="F1, F2", lx=-14, ly=14),
  dict(x1=200, y1=300, x2=280, y2=470, label="F1, F2", lx=-18, ly=36),
  dict(x1=530, y1=110, x2=700, y2=110, label="OTLP", amber=True, lx=0, ly=-8),
  dict(x1=530, y1=230, x2=700, y2=230, label="OTLP", amber=True, lx=0, ly=-8),
  dict(x1=530, y1=350, x2=700, y2=350, label="OTLP", amber=True, lx=0, ly=-8),
  dict(x1=530, y1=450, x2=700, y2=400, label="OTLP", amber=True, lx=0, ly=-8),
  dict(x1=530, y1=500, x2=700, y2=500, label="schema diff (production)", lx=0, ly=-8),
 ],
 notes=[dict(x=50, y=555, text="verify.sh sends its own trace id with F1 and F2, reads the trace from Tempo and the log records from Loki, and switches the debug category on and off.", size=12, color="#555555")])
