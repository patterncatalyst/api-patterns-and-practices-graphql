"""Spec for assets/diagrams/A-route-to-edge.{svg,excalidraw}. Regenerate: python3 -I diagrams/A-route-to-edge.py

Drawn from the rendered Routes and Services of examples/99-appendix-a-openshift-crc/helm
(helm template): six Routes in project gql-appendix-a, hosts <name>-gql-appendix-a.apps-crc.testing.
Two Routes target the edge Service on its plain ports (quarkus 8080, python 8081); the
internal instances and Grafana have edge-TLS Routes of their own; Keycloak has an edge-TLS
Route too and reads the forwarded headers, so its https URL is the issuer the stacks pin. No cluster output is shown.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=470, label="OpenShift Local, project gql-appendix-a"),
]
nodes = [
    dict(x=40, y=120, w=150, h=100, style="user", lines=["client", "curl --cacert", "ingress-ca.crt", "HTTPS, WSS, SSE"]),
    dict(x=235, y=100, w=190, h=140, style="accent", lines=["router", "edge TLS with the", "ingress certificate", "HTTP redirected", "timeout 1h on", "the edge Routes"]),
    dict(x=490, y=85, w=200, h=75, style="box", lines=["Routes quarkus, python", "to Service edge", "plain 8080, 8081"]),
    dict(x=740, y=85, w=220, h=75, style="box", lines=["edge (nginx)", "64k limit, /graphql, /events/", "upgrade headers kept"]),
    dict(x=740, y=180, w=220, h=60, style="sub", lines=["public quarkus, python", "ClusterIP :8080, introspection off"]),
    dict(x=490, y=270, w=200, h=65, style="box", lines=["Routes quarkus-internal,", "python-internal (edge TLS)"]),
    dict(x=740, y=270, w=220, h=65, style="sub", lines=["internal instances", "introspection on"]),
    dict(x=490, y=365, w=200, h=65, style="box", lines=["Route keycloak (edge TLS)", "X-Forwarded headers"]),
    dict(x=740, y=365, w=220, h=65, style="box", lines=["keycloak 26.8.1", "issuer = the Route's URL"]),
    dict(x=490, y=450, w=200, h=55, style="box", lines=["Route grafana (edge TLS)"]),
    dict(x=740, y=450, w=220, h=55, style="accent", lines=["lgtm: Grafana, Tempo, Loki"]),
]
edges = [
    dict(x1=190, y1=170, x2=235, y2=170, amber=True, label="HTTPS", lx=0, ly=-12),
    dict(x1=425, y1=140, x2=490, y2=122),
    dict(x1=425, y1=190, x2=490, y2=300),
    dict(x1=425, y1=215, x2=490, y2=395),
    dict(x1=425, y1=235, x2=490, y2=475),
    dict(x1=690, y1=122, x2=740, y2=122, amber=True, label="HTTP", lx=0, ly=-12),
    dict(x1=850, y1=160, x2=850, y2=180, amber=True),
    dict(x1=690, y1=302, x2=740, y2=302, amber=True),
    dict(x1=690, y1=397, x2=740, y2=397, amber=True),
    dict(x1=690, y1=477, x2=740, y2=477, amber=True),
]
notes = [
    dict(x=500, y=28, text="TLS ends at the router; everything behind it speaks plain HTTP inside the project", anchor="middle", bold=True),
    dict(x=500, y=545, text="Hosts are <name>-gql-appendix-a.apps-crc.testing. Values from the rendered Routes and Services; no cluster output is shown.", anchor="middle", size=12, color="#555555"),
]
g.emit("A-route-to-edge", 1000, 570, bands=bands, nodes=nodes, edges=edges, notes=notes)
