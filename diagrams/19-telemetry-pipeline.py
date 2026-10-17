"""Spec for assets/diagrams/19-telemetry-pipeline.{svg,excalidraw}. Regenerate: python3 -I diagrams/19-telemetry-pipeline.py

Drawn from examples/19-observability/compose.yaml: both stacks export traces,
metrics and logs over OTLP gRPC to the collector inside the lgtm service (port
4317, internal to the compose network); Tempo, Prometheus and Loki are
published on 8293, 8294 and 8295, Grafana on 8292. A caller's traceparent
header arrives with the request and the server span joins that trace. Tempo's
metrics generator remote-writes span metrics to Prometheus.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=60, w=250, h=400, label="Two stacks"),
    dict(x=300, y=60, w=680, h=400, label="lgtm (grafana/otel-lgtm)"),
]
nodes = [
    dict(x=40, y=100, w=210, h=100, style="box", lines=["quarkus  :8290", "quarkus-opentelemetry", "graphql-java instrumentation", "Telemetry observer"]),
    dict(x=40, y=290, w=210, h=100, style="box", lines=["python  :8291", "opentelemetry-instrument", "OpenTelemetryExtension", "OperationMetrics"]),
    dict(x=330, y=190, w=170, h=100, style="accent", lines=["OpenTelemetry", "Collector", "OTLP gRPC :4317", "(not published)"]),
    dict(x=620, y=90, w=160, h=60, style="box", lines=["Tempo", "traces  :8293"]),
    dict(x=620, y=210, w=160, h=60, style="box", lines=["Prometheus", "metrics  :8294"]),
    dict(x=620, y=330, w=160, h=60, style="box", lines=["Loki", "logs  :8295"]),
    dict(x=820, y=210, w=140, h=60, style="user", lines=["Grafana", ":8292"]),
    dict(x=60, y=222, w=170, h=46, style="ghost", lines=["traceparent in", "from the caller"]),
]
edges = [
    dict(x1=250, y1=150, x2=330, y2=225, amber=True, label="OTLP", lx=-4, ly=-14),
    dict(x1=250, y1=340, x2=330, y2=262, amber=True, label="OTLP", lx=-4, ly=22),
    dict(x1=500, y1=215, x2=620, y2=125, label="spans", lx=-6, ly=-6),
    dict(x1=500, y1=240, x2=620, y2=240, label="metrics", lx=0, ly=-8),
    dict(x1=500, y1=265, x2=620, y2=350, label="log records", lx=-34, ly=18),
    dict(x1=700, y1=150, x2=700, y2=210, dashed=True, amber=True, label="span metrics", lx=-44, ly=0),
    dict(x1=780, y1=125, x2=860, y2=210, dashed=True),
    dict(x1=780, y1=240, x2=820, y2=240, dashed=True),
    dict(x1=780, y1=355, x2=870, y2=270, dashed=True),
    dict(x1=145, y1=222, x2=145, y2=200, dashed=True),
    dict(x1=145, y1=268, x2=145, y2=290, dashed=True),
]
notes = [
    dict(x=500, y=28, text="Three signals leave over one protocol, and one trace id joins them", anchor="middle", bold=True),
    dict(x=500, y=490, text="The trace id travels in the traceparent header, spans carry it, and log records carry it as structured metadata. Grafana reads all three stores.", anchor="middle", size=12, color="#555555"),
]
g.emit("19-telemetry-pipeline", 1000, 510, bands=bands, nodes=nodes, edges=edges, notes=notes)
