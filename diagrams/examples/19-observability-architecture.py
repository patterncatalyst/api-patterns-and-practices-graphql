"""Spec for examples/19-observability/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/19-observability-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "19-observability")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/19-observability - compose stack (gql-ch19-observability)")],
 nodes=[
  dict(x=50, y=210, w=170, h=70, style="user", lines=["curl / verify.sh", "client + traceparent"]),
  dict(x=300, y=70, w=270, h=140, style="box", lines=["quarkus", "SmallRye GraphQL (code-first)", "quarkus-opentelemetry", "graphql-java instrumentation", "Telemetry.java (GraphQL.Builder event)", ":8080 -> host :8290 /graphql"]),
  dict(x=300, y=290, w=270, h=140, style="box", lines=["python", "Strawberry on FastAPI (code-first)", "opentelemetry-instrument", "OpenTelemetryExtension + OperationMetrics", "app/telemetry.py", ":8080 -> host :8291 /graphql"]),
  dict(x=700, y=70, w=250, h=140, style="accent", lines=["lgtm (otel-lgtm 0.37.0)", "Collector, Tempo, Prometheus,", "Loki, Grafana", "Grafana 8292, Tempo 8293,", "Prometheus 8294, Loki 8295"]),
  dict(x=700, y=290, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
 ],
 edges=[
  dict(x1=220, y1=235, x2=300, y2=150, label="FanOut, TrackCargo", lx=-30, ly=-30),
  dict(x1=220, y1=255, x2=300, y2=350, label="FanOut, TrackCargo", lx=-30, ly=30),
  dict(x1=570, y1=140, x2=700, y2=140, label="OTLP", amber=True, lx=0, ly=-8),
  dict(x1=570, y1=360, x2=700, y2=200, label="OTLP", amber=True, lx=-6, ly=30),
  dict(x1=570, y1=390, x2=700, y2=350, label="introspect + diff", lx=-8, ly=18),
  dict(x1=700, y1=205, x2=220, y2=228, dashed=True, label="reads back by trace id", lx=0, ly=14),
 ],
 notes=[dict(x=50, y=478, text="verify.sh sends its own trace id, then reads the trace from Tempo, the metrics from Prometheus and the log records from Loki.", size=12, color="#555555")])
