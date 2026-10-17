"""Spec for examples/25-docker-compose/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/25-docker-compose-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "25-docker-compose")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/25-docker-compose - compose stack (gql-ch25-compose)")],
 nodes=[
  dict(x=40, y=200, w=160, h=80, style="user", lines=["curl / verify.sh", "client + traceparent"]),
  dict(x=260, y=150, w=200, h=180, style="accent", lines=["edge (nginx-126 10.2)", "TLS 1.3, 64k body limit", "/graphql only", "host 8350 -> :8443", "host 8351 -> :8444"]),
  dict(x=540, y=70, w=200, h=100, style="box", lines=["quarkus", "gql-ch25-quarkus:1.0", ":8080, backend network"]),
  dict(x=540, y=200, w=200, h=100, style="box", lines=["python", "gql-ch25-python:1.0", ":8080, backend network"]),
  dict(x=540, y=340, w=200, h=120, style="accent", lines=["lgtm (otel-lgtm 0.37.0)", "Collector, Tempo, Prometheus,", "Loki, Grafana", "127.0.0.1 8352 to 8355"]),
  dict(x=260, y=370, w=200, h=90, style="sub", lines=["configs / secrets", "edge_conf, edge_tls_crt,", "edge_tls_key"]),
  dict(x=800, y=200, w=160, h=100, style="sub", lines=["contracts/schema/", "shipping/*.graphql", "diffed with both stacks"]),
 ],
 edges=[
  dict(x1=200, y1=240, x2=260, y2=240, label="TLS 1.3", lx=0, ly=-8),
  dict(x1=460, y1=200, x2=540, y2=120, label="8080", lx=0, ly=-8),
  dict(x1=460, y1=260, x2=540, y2=250, label="8080", lx=0, ly=-8),
  dict(x1=640, y1=300, x2=640, y2=340, amber=True, label="OTLP from both", lx=50, ly=0),
  dict(x1=360, y1=370, x2=360, y2=330, dashed=True),
  dict(x1=740, y1=250, x2=800, y2=250, dashed=True),
 ],
 notes=[dict(x=40, y=482, text="verify.sh reads each result through the edge, follows a trace id to Tempo and Loki, and reads limits and policies back from the engine.", size=12, color="#555555")])
