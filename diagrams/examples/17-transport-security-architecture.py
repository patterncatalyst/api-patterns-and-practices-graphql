"""Spec for examples/17-transport-security/architecture.{svg,excalidraw}.

Regenerate with:  python3 -I diagrams/examples/17-transport-security-architecture.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))  # -I drops the script dir from sys.path

import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "examples" / "17-transport-security")
g.emit("architecture", 1000, 560,
 bands=[dict(x=20, y=20, w=960, h=520, label="examples/17-transport-security - compose stack (gql-ch17-transport), HTTPS only")],
 nodes=[
  dict(x=50, y=240, w=170, h=80, style="user", lines=["curl / verify.sh", "client", "trusts ca.crt only"]),
  dict(x=300, y=60, w=270, h=100, style="accent", lines=["quarkus (public)", "TLS registry, TLS 1.3 only", "introspection off, 415, 413", ":8443 -> host :8270"]),
  dict(x=300, y=175, w=270, h=100, style="box", lines=["quarkus-internal", "same image, introspection on", "", ":8443 -> host :8272"]),
  dict(x=300, y=290, w=270, h=100, style="accent", lines=["python (public)", "uvicorn TLS, DisableIntrospection", "no suggestions, IDE or GET", ":8443 -> host :8271"]),
  dict(x=300, y=405, w=270, h=100, style="box", lines=["python-internal", "same image, introspection on", "", ":8443 -> host :8273"]),
  dict(x=700, y=60, w=250, h=100, style="box", lines=["gen-certs.sh", "ca.crt, tls.crt, tls.key", "(scratch dir, git-ignored)"]),
  dict(x=700, y=240, w=250, h=100, style="accent", lines=["contracts/schema/", "shipping/*.graphql", "(canonical SDL, single source)"]),
  dict(x=700, y=440, w=250, h=60, style="ghost", lines=["otel-lgtm", "(compose.observability.yaml)"]),
 ],
 edges=[
  dict(x1=220, y1=270, x2=300, y2=110, label="https", lx=-22, ly=-30),
  dict(x1=220, y1=275, x2=300, y2=225),
  dict(x1=220, y1=290, x2=300, y2=340),
  dict(x1=220, y1=305, x2=300, y2=455),
  dict(x1=700, y1=110, x2=570, y2=110, label="mounted /certs", dashed=True, lx=-6, ly=-16),
  dict(x1=570, y1=225, x2=700, y2=280, label="introspect + diff", amber=True, lx=14, ly=-18),
  dict(x1=570, y1=455, x2=700, y2=315, label="introspect + diff", amber=True, lx=22, ly=44),
  dict(x1=570, y1=490, x2=700, y2=480, label="OTLP", dashed=True, lx=-2, ly=18),
 ],
 notes=[dict(x=50, y=525, text="Only the internal instances are diffed against the canonical SDL; the public ones refuse introspection.", size=12, color="#555555")])
