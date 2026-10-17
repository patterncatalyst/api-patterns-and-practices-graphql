"""Spec for examples/99-appendix-a-openshift-crc/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/99-appendix-a-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "99-appendix-a-openshift-crc")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/99-appendix-a-openshift-crc - release gql-appendix-a in project gql-appendix-a on OpenShift Local")],
 nodes=[
  dict(x=40, y=240, w=170, h=90, style="user", lines=["scripts/smoke.sh", "curl --cacert ingress CA", "*.apps-crc.testing"]),
  dict(x=260, y=220, w=190, h=130, style="accent", lines=["router", "6 Routes", "edge TLS, HTTP redirected", "ingress certificate"]),
  dict(x=520, y=70, w=200, h=90, style="box", lines=["edge (nginx)", "plain 8080, 8081", "from Chapter 27's chart"]),
  dict(x=520, y=190, w=200, h=90, style="box", lines=["quarkus, python", "public and internal", "restricted-v2"]),
  dict(x=520, y=310, w=200, h=70, style="box", lines=["keycloak 26.8.1", "issuer = its Route URL"]),
  dict(x=520, y=410, w=200, h=90, style="accent", lines=["lgtm (otel-lgtm 0.37.0)", "ServiceAccount gql-lgtm", "anyuid RoleBinding"]),
  dict(x=780, y=70, w=180, h=130, style="sub", lines=["BuildConfig x2", "ImageStream x2", "Docker strategy", "binary source"]),
  dict(x=780, y=240, w=180, h=110, style="ghost", lines=["scripts/up.sh", "inventory, build,", "rollout, helm test"]),
  dict(x=780, y=390, w=180, h=110, style="ghost", lines=["scripts/down.sh", "uninstall, delete project,", "compare, crc stop"]),
 ],
 edges=[
  dict(x1=210, y1=285, x2=260, y2=285, amber=True, label="HTTPS", lx=0, ly=-8),
  dict(x1=450, y1=260, x2=520, y2=115, label="/graphql", lx=-14, ly=-8),
  dict(x1=450, y1=285, x2=520, y2=235),
  dict(x1=450, y1=310, x2=520, y2=345),
  dict(x1=450, y1=340, x2=520, y2=450),
  dict(x1=620, y1=160, x2=620, y2=190, dashed=True),
  dict(x1=780, y1=135, x2=720, y2=235, dashed=True, label="images", lx=14, ly=-6),
 ],
 notes=[dict(x=50, y=525, text="Validated without a cluster: helm lint, kubeconform with the OpenShift schemas, ShellCheck.", size=12, color="#555555")])
