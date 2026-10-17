"""Spec for assets/diagrams/26-cluster-topology.{svg,excalidraw}. Regenerate: python3 -I diagrams/26-cluster-topology.py

Drawn from one run of examples/26-minikube/scripts/smoke.sh on the profile
gql-tracking (Kubernetes v1.37.1): a ListCargos request to the Quarkus edge
NodePort 30360 with trace id 14d6ffd026bf23a05da7303b53bac64d, which Tempo
answered with 11 spans whose resource carried k8s.pod.name
quarkus-588766b5bf-dxv9z.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=205, y=50, w=780, h=500, label="node container gql-tracking: containerd, Kubernetes v1.37.1, namespace gql-ch26")]
nodes = [
    dict(x=20, y=110, w=140, h=90, style="user", lines=["host", "curl --cacert ca.crt", "127.0.0.1:30360"]),
    dict(x=225, y=110, w=160, h=90, style="box", lines=["Service edge", "NodePort 8443:30360", "published by Docker"]),
    dict(x=417, y=95, w=160, h=120, style="box", lines=["edge pod", "nginx, TLS 1.3, 64k", "Secret gql-ch26-edge-tls", "ConfigMap edge-config", "only /graphql routed"]),
    dict(x=609, y=110, w=160, h=90, style="box", lines=["Service quarkus", "ClusterIP :8080", "ready pods only"]),
    dict(x=801, y=95, w=160, h=120, style="accent", lines=["quarkus pod", "quarkus-588766b5bf-dxv9z", "startup, ready, live probes", "ConfigMap env", "downward API: pod name"]),
    dict(x=20, y=310, w=140, h=90, style="user", lines=["host", "GET /api/traces/<id>", "127.0.0.1:30363"]),
    dict(x=609, y=310, w=160, h=90, style="box", lines=["Service lgtm-ui", "NodePort 3200:30363", "Tempo, Loki, Grafana"]),
    dict(x=801, y=295, w=160, h=120, style="box", lines=["lgtm pod", "otel-lgtm 0.37.0", "OTLP :4317 via", "Service lgtm", "Tempo, Loki, Prometheus"]),
    dict(x=225, y=450, w=736, h=70, style="ink", lines=["trace 14d6ffd026bf23a05da7303b53bac64d in Tempo: 11 spans", "resource k8s.pod.name = quarkus-588766b5bf-dxv9z, k8s.namespace.name = gql-ch26"]),
]
edges = [
    dict(x1=160, y1=155, x2=225, y2=155, amber=True),
    dict(x1=385, y1=155, x2=417, y2=155, amber=True),
    dict(x1=577, y1=155, x2=609, y2=155, amber=True),
    dict(x1=769, y1=155, x2=801, y2=155, amber=True),
    dict(x1=881, y1=215, x2=881, y2=295, label="OTLP", lx=26, ly=0),
    dict(x1=160, y1=355, x2=609, y2=355, label="Docker-published 30363", lx=0, ly=-8),
    dict(x1=769, y1=355, x2=801, y2=355),
    dict(x1=881, y1=415, x2=881, y2=450, dashed=True),
]
notes = [
    dict(x=500, y=28, text="From a host port to a pod, and from the pod's trace back to its name", anchor="middle", bold=True),
    dict(x=225, y=575, text="Host access is only through NodePorts published when the profile was created; the Service names resolve inside the cluster.", size=12, color="#555555"),
]
g.emit("26-cluster-topology", 1000, 590, bands=bands, nodes=nodes, edges=edges, notes=notes)
