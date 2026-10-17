"""Spec for assets/diagrams/24-dev-vs-prod-surfaces.{svg,excalidraw}. Regenerate: python3 -I diagrams/24-dev-vs-prod-surfaces.py

Drawn from the answers examples/24-debugging/verify.sh asserts, per row:
  GraphQL IDE      quarkus-dev 8342 GET /q/graphql-ui/ 200; python-dev 8343 GET /graphql
                   (Accept: text/html) 200; quarkus 8340 and python 8341: 404
  Dev UI           quarkus-dev 8342 GET /q/dev-ui/ 200; quarkus 8340: 404
  Payload logging  quarkus-dev log holds the LegsOfJkl document; quarkus log holds none
  Level switch     POST /q/logging-manager (Quarkus), POST /debug/loggers (Python),
                   both with TRACKING_DEBUG_ENDPOINTS=true, on all four instances
  Masked errors    "Internal server error." on all four
  extensions.traceId on every execution error on all four
  Telemetry        all four export to lgtm (Grafana 8344, Tempo 8345, Prometheus 8346, Loki 8347)
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

LX, DX, PX, W, H = 30, 250, 625, 345, 54
rows = [
    ("GraphQL IDE", ("accent", ["/q/graphql-ui (Quarkus)", "GraphiQL at /graphql (Python)"]), ("ghost", ["404 on both stacks"])),
    ("Dev UI", ("accent", ["/q/dev-ui (Quarkus)"]), ("ghost", ["404"])),
    ("Payload logging", ("accent", ["each document in the log (Quarkus)"]), ("ghost", ["off"])),
    ("Level switch (lab)", ("box", ["/q/logging-manager, /debug/loggers", "with TRACKING_DEBUG_ENDPOINTS=true"]), ("box", ["the same"])),
    ("Masked errors", ("box", ["Internal server error."]), ("box", ["the same"])),
    ("extensions.traceId", ("box", ["on every execution error"]), ("box", ["the same"])),
    ("Traces and logs", ("box", ["OTLP to lgtm"]), ("box", ["the same"])),
]
bands = [dict(x=20, y=50, w=960, h=104 + len(rows) * 66)]
nodes = [
    dict(x=DX, y=72, w=W, h=46, style="user", lines=["Development instance", "quarkus-dev :8342, python-dev :8343"]),
    dict(x=PX, y=72, w=W - 15, h=46, style="user", lines=["Production instance", "quarkus :8340, python :8341"]),
]
notes = [dict(x=500, y=28, text="The development surfaces exist on the development instances and nowhere else", anchor="middle", bold=True)]
y = 138
for label, dev, prod in rows:
    notes.append(dict(x=LX, y=y + 32, text=label, size=12.5, bold=True))
    nodes.append(dict(x=DX, y=y, w=W, h=H, style=dev[0], lines=dev[1]))
    nodes.append(dict(x=PX, y=y, w=W - 15, h=H, style=prod[0], lines=prod[1]))
    y += 66
notes.append(dict(x=500, y=y + 40, text="Amber boxes are development-only; dashed boxes are absent from production. Masking, the trace id and telemetry do not depend on the profile.", anchor="middle", size=12, color="#555555"))
g.emit("24-dev-vs-prod-surfaces", 1000, y + 60, bands=bands, nodes=nodes, edges=[], notes=notes)
