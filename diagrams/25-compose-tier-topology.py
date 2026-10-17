"""Spec for assets/diagrams/25-compose-tier-topology.{svg,excalidraw}. Regenerate: python3 -I diagrams/25-compose-tier-topology.py

The compose project gql-ch25-compose of examples/25-docker-compose: the three
networks, the edge with its config and secrets, both stacks with their health
checks and limits, and the observability backend. The numbers on the services
are the start order that depends_on with condition service_healthy enforces.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=210, y=50, w=200, h=440, label="public"),
    dict(x=430, y=50, w=340, h=440, label="backend (internal: true)"),
    dict(x=790, y=50, w=190, h=440, label="ops, host 127.0.0.1"),
]
nodes = [
    dict(x=20, y=190, w=170, h=100, style="user", lines=["client", "verify.sh, curl", "8350 and 8351, TLS 1.3"]),
    dict(x=225, y=110, w=170, h=140, style="accent", lines=["3. edge", "ubi10/nginx-126", "TLS 1.3, body under 64k", "only /graphql routed", "0.25 cpu, 64m"]),
    dict(x=225, y=300, w=170, h=110, style="sub", lines=["configs and secrets", "edge_conf is nginx.conf", "edge_tls_crt, edge_tls_key", "mounted under /run/secrets"]),
    dict(x=450, y=90, w=300, h=100, style="box", lines=["2. quarkus  gql-ch25-quarkus:1.0", "healthy at /q/health/ready", "1.0 cpu, 768m, no published port"]),
    dict(x=450, y=215, w=300, h=100, style="box", lines=["2. python  gql-ch25-python:1.0", "healthy at /health/ready", "0.5 cpu, 384m, no published port"]),
    dict(x=450, y=345, w=300, h=120, style="accent", lines=["1. lgtm  otel-lgtm 0.37.0", "collector, Tempo, Prometheus,", "Loki, Grafana", "healthy when all three answer"]),
    dict(x=805, y=345, w=160, h=120, style="box", lines=["Grafana 8352", "Tempo 8353", "Prometheus 8354", "Loki 8355"]),
]
edges = [
    dict(x1=190, y1=240, x2=225, y2=180, label="TLS", lx=-6, ly=-10),
    dict(x1=395, y1=150, x2=450, y2=140, label="8080", lx=0, ly=-8),
    dict(x1=395, y1=210, x2=450, y2=255, label="8080", lx=0, ly=12),
    dict(x1=600, y1=315, x2=600, y2=345, amber=True, label="OTLP from both", lx=60, ly=0),
    dict(x1=750, y1=405, x2=805, y2=405),
]
notes = [
    dict(x=500, y=28, text="One project, three networks, three start stages", anchor="middle", bold=True),
    dict(x=500, y=516, text="Only the edge publishes beyond loopback. The backend network has no route to the host, so the stacks are reached through the edge.", anchor="middle", size=12, color="#555555"),
]
g.emit("25-compose-tier-topology", 1000, 540, bands=bands, nodes=nodes, edges=edges, notes=notes)
