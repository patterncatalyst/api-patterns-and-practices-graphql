"""Spec for assets/diagrams/26-compose-to-kubernetes.{svg,excalidraw}. Regenerate: python3 -I diagrams/26-compose-to-kubernetes.py

Chapter 25's Compose concepts (examples/25-docker-compose/compose.yaml) beside
the Kubernetes objects of examples/26-minikube/helm/templates that replace them.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

rows = [
    (["services: quarkus, python", "compose.yaml"], ["Deployment + ClusterIP Service per stack", "stack-deployment.yaml, stack-service.yaml"]),
    (["ports: 8350:8443, 8351:8444", "compose.yaml, edge"], ["NodePort Service 30360, 30361", "edge-service.yaml"]),
    (["env_file: env/quarkus.env", "env/*.env"], ["ConfigMap, read with envFrom", "stack-configmap.yaml"]),
    (["configs: edge_conf", "compose.yaml"], ["ConfigMap mounted as nginx.conf", "edge-configmap.yaml"]),
    (["secrets: edge_tls_crt, edge_tls_key", "gen-certs.sh"], ["TLS Secret from genCA, kept with lookup", "tls-secret.yaml"]),
    (["healthcheck + depends_on", "service_healthy"], ["startup, readiness, liveness probes", "stack-deployment.yaml"]),
    (["deploy.resources.limits", "cpus, memory"], ["resources requests and limits", "values.yaml"]),
    (["restart + stop_grace_period", "unless-stopped, 15s"], ["kubelet restarts; grace period 30s", "preStop sleep, rolling update"]),
    (["networks: backend (internal)", "public, ops"], ["NetworkPolicy per tier", "networkpolicy.yaml"]),
]

bands = [
    dict(x=20, y=50, w=400, h=480, label="Chapter 25: Compose"),
    dict(x=580, y=50, w=400, h=480, label="Chapter 26: Helm chart on Kubernetes"),
]
nodes, edges = [], []
for i, (left, right) in enumerate(rows):
    y = 80 + i * 49
    nodes.append(dict(x=40, y=y, w=360, h=42, style="box", lines=left))
    nodes.append(dict(x=600, y=y, w=360, h=42, style="accent", lines=right))
    edges.append(dict(x1=400, y1=y + 21, x2=600, y2=y + 21, amber=True))
notes = [
    dict(x=500, y=28, text="Each Compose concept and the chart template that carries it", anchor="middle", bold=True),
    dict(x=500, y=556, text="The images, the environment contract and the edge configuration do not change between the two tiers.", anchor="middle", size=12, color="#555555"),
]
g.emit("26-compose-to-kubernetes", 1000, 580, bands=bands, nodes=nodes, edges=edges, notes=notes)
