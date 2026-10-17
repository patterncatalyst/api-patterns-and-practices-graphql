"""Spec for assets/diagrams/A-same-chart-on-openshift.{svg,excalidraw}. Regenerate: python3 -I diagrams/A-same-chart-on-openshift.py

Chapter 27's chart (examples/27-final-project/helm) in the middle, with the values
the minikube tier gives it on the left and the wrapper chart of
examples/99-appendix-a-openshift-crc/helm on the right. The wrapper depends on the
chart through file://../../27-final-project/helm and adds only OpenShift objects.
Values are read from the two values files and the rendered manifests.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=290, h=300, label="Chapter 27 values on minikube"),
    dict(x=345, y=50, w=310, h=300, label="Chapter 27 chart, unchanged"),
    dict(x=690, y=50, w=290, h=300, label="Appendix A wrapper chart"),
]
nodes = [
    dict(x=40, y=95, w=250, h=70, style="box", lines=["NodePort Services", "30370 to 30378 on 127.0.0.1"]),
    dict(x=40, y=180, w=250, h=70, style="box", lines=["imagePullPolicy: Never", "images loaded into the node"]),
    dict(x=40, y=265, w=250, h=70, style="box", lines=["edge terminates TLS 1.3", "chart-generated certificate"]),
    dict(x=365, y=95, w=270, h=110, style="accent", lines=["gql-ch27-final 1.0.0", "edge, quarkus, python, keycloak,", "lgtm, NetworkPolicy, helm test", "no OpenShift kind, no UID"]),
    dict(x=365, y=225, w=270, h=120, style="sub", lines=["values it exposes", "edge.tls.enabled, *.service.type", "image.repository and pullPolicy", "identity.issuer, keycloak.proxyHeaders", "lgtm.serviceAccountName, seccompProfile"]),
    dict(x=710, y=95, w=250, h=70, style="box", lines=["Chart.yaml dependency, alias final", "file://../../27-final-project/helm"]),
    dict(x=710, y=180, w=250, h=70, style="box", lines=["final.* values", "ClusterIP, plain edge, IfNotPresent"]),
    dict(x=710, y=265, w=250, h=70, style="box", lines=["Routes x6, BuildConfigs x2,", "ImageStreams x2, anyuid RoleBinding"]),
    dict(x=40, y=385, w=920, h=90, style="ghost", lines=["Application code, Containerfiles and images: the same in every tier", "quarkus/ and python/ of Chapter 27 build with their Containerfile unchanged;", "the cluster only changes who builds them, who terminates TLS and which SCC admits a pod"]),
]
edges = [
    dict(x1=290, y1=130, x2=365, y2=150, amber=True, label="values", lx=0, ly=-12),
    dict(x1=710, y1=130, x2=635, y2=150, amber=True, label="depends on", lx=0, ly=-12),
    dict(x1=710, y1=215, x2=635, y2=280, amber=True, label="override", lx=0, ly=-10),
    dict(x1=500, y1=335, x2=500, y2=385, dashed=True),
]
notes = [
    dict(x=500, y=28, text="The wrapper adds Routes, builds and one SCC binding; the chart it depends on does not change", anchor="middle", bold=True),
    dict(x=500, y=500, text="Only examples/99-appendix-a-openshift-crc renders route.openshift.io, build.openshift.io and image.openshift.io objects.", anchor="middle", size=12, color="#555555"),
]
g.emit("A-same-chart-on-openshift", 1000, 520, bands=bands, nodes=nodes, edges=edges, notes=notes)
