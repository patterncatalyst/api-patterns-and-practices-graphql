"""Spec for examples/27-final-project/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/27-final-project-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "27-final-project")
g.emit("architecture", 1000, 520,
 bands=[dict(x=20, y=20, w=960, h=480, label="examples/27-final-project - compose stack (gql-ch27-final)")],
 nodes=[
  dict(x=40, y=200, w=150, h=80, style="user", lines=["curl / verify.sh", "bearer token"]),
  dict(x=240, y=140, w=200, h=200, style="accent", lines=["edge (nginx-126 10.2)", "TLS 1.3, 64k body limit", "/graphql, /events/", "host 8370 -> :8443", "host 8371 -> :8444"]),
  dict(x=510, y=50, w=210, h=90, style="box", lines=["quarkus, python", "gql-ch27-*:1.0", "public, introspection off"]),
  dict(x=510, y=160, w=210, h=90, style="sub", lines=["internal instances", "same images, introspection on", "127.0.0.1 8372, 8373"]),
  dict(x=780, y=50, w=180, h=90, style="box", lines=["keycloak 26.8.1", "realm shipping", "127.0.0.1 8374"]),
  dict(x=780, y=160, w=180, h=90, style="accent", lines=["lgtm 0.37.0", "127.0.0.1 8375 to 8378"]),
  dict(x=510, y=290, w=210, h=70, style="sub", lines=["client (profile)", "gql-ch27-client:1.0"]),
  dict(x=510, y=390, w=210, h=70, style="sub", lines=["load (profile)", "gql-ch27-load:1.0, k6 v2.3.0"]),
  dict(x=240, y=390, w=200, h=70, style="sub", lines=["configs / secrets", "edge_conf, ca_crt,", "edge_tls_crt, edge_tls_key"]),
 ],
 edges=[
  dict(x1=190, y1=240, x2=240, y2=240, label="TLS 1.3", lx=0, ly=-8),
  dict(x1=440, y1=200, x2=510, y2=100, label="8080", lx=0, ly=-8),
  dict(x1=720, y1=95, x2=780, y2=95, amber=True, label="JWKS", lx=0, ly=-8),
  dict(x1=720, y1=205, x2=780, y2=205, amber=True, label="OTLP", lx=0, ly=-8),
  dict(x1=510, y1=325, x2=440, y2=280, dashed=True),
  dict(x1=510, y1=425, x2=440, y2=300, dashed=True),
  dict(x1=340, y1=390, x2=340, y2=340, dashed=True),
 ],
 notes=[dict(x=40, y=482, text="verify.sh reads each result through the edge, runs the subscription client and k6 on the backend network, and diffs the internal instances with the contract.", size=12, color="#555555")])
