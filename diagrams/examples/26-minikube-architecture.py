"""Spec for examples/26-minikube/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/26-minikube-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "26-minikube")
g.emit("architecture", 1000, 600,
 bands=[dict(x=20, y=20, w=960, h=560, label="examples/26-minikube - Helm release gql-ch26 on minikube profile gql-tracking")],
 nodes=[
  dict(x=40, y=250, w=170, h=80, style="user", lines=["scripts/smoke.sh", "curl + trace id", "127.0.0.1:30360-30365"]),
  dict(x=280, y=230, w=200, h=120, style="box", lines=["edge (nginx, TLS 1.3)", "Secret gql-ch26-edge-tls", "ConfigMap edge-config", "NodePort 30360, 30361"]),
  dict(x=560, y=70, w=220, h=110, style="box", lines=["quarkus", "gql-ch25-quarkus:1.0", "3 probes, ConfigMap, downward API", "ClusterIP :8080"]),
  dict(x=560, y=230, w=220, h=110, style="box", lines=["python", "gql-ch25-python:1.0", "3 probes, ConfigMap, downward API", "ClusterIP :8080"]),
  dict(x=560, y=410, w=380, h=120, style="accent", lines=["lgtm (otel-lgtm 0.37.0)", "OTLP :4317 (ClusterIP lgtm)", "Grafana 30362, Tempo 30363,", "Prometheus 30364, Loki 30365"]),
  dict(x=280, y=430, w=200, h=90, style="kernel", lines=["NetworkPolicy", "backends accept edge and test", "lgtm accepts OTLP in-release"]),
  dict(x=820, y=70, w=140, h=190, style="ghost", lines=["helm test", "gql-ch26-graphql-test", "queries both stacks", "through the edge"]),
 ],
 edges=[
  dict(x1=210, y1=290, x2=280, y2=290, amber=True, label="HTTPS", lx=0, ly=-8),
  dict(x1=480, y1=270, x2=560, y2=125, label="/graphql", lx=-6, ly=-14),
  dict(x1=480, y1=300, x2=560, y2=285, label="/graphql", lx=0, ly=14),
  dict(x1=670, y1=340, x2=670, y2=410, amber=True, label="OTLP", lx=22, ly=0),
  dict(x1=210, y1=330, x2=560, y2=450, label="Tempo and Loki by trace id", lx=-20, ly=-12),
 ],
 notes=[dict(x=50, y=555, text="smoke.sh sends its own trace id through the edge, reads the trace from Tempo and checks the pod name in it.", size=12, color="#555555")])
