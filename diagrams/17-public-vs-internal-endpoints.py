"""Spec for assets/diagrams/17-public-vs-internal-endpoints.{svg,excalidraw}. Regenerate: python3 -I diagrams/17-public-vs-internal-endpoints.py

One image per stack, deployed twice by examples/17-transport-security/compose.yaml:
public on host 8270 (Quarkus) and 8271 (Python), internal on 8272 and 8273. The settings
listed are those verify.sh asserts. Introspection, field suggestions, the IDE and GET
queries differ; TLS, HSTS, CORS, the content-type check and the body limit (Quarkus) do not.
Introspection is refused through graphql-java's Introspection.enabledJvmWide(false) on Quarkus.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=170, w=470, h=250, label="Public instance (8270, 8271)"),
    dict(x=510, y=170, w=470, h=250, label="Internal instance (8272, 8273)"),
]
nodes = [
    dict(x=300, y=54, w=400, h=70, style="box", lines=["One image per stack", "the same code, configured by environment"]),
    dict(x=45, y=215, w=420, h=150, style="accent", lines=[
        "introspection off: __schema, __type refused",
        "field suggestions off (Python)",
        "IDE off, GET queries off",
        "TLS, HSTS, CORS, JSON-only POST, body limit (Quarkus)"]),
    dict(x=535, y=215, w=420, h=150, style="box", lines=[
        "introspection on",
        "field suggestions on (Python)",
        "IDE on (Python), GET queries on (Python)",
        "TLS, HSTS, CORS, JSON-only POST, body limit (Quarkus)"]),
    dict(x=45, y=455, w=200, h=60, style="user", lines=["Browsers, partners", "the public internet"]),
    dict(x=535, y=455, w=200, h=60, style="user", lines=["CI and developers", "assert_sdl_conforms"]),
    dict(x=765, y=455, w=190, h=60, style="ghost", lines=["SDL export at build", "(Chapter 5), no endpoint"]),
]
edges = [
    dict(x1=400, y1=124, x2=255, y2=215, label="deploy", lx=-40, ly=-6),
    dict(x1=600, y1=124, x2=880, y2=215, label="deploy", lx=30, ly=-6),
    dict(x1=145, y1=455, x2=145, y2=365, amber=True),
    dict(x1=635, y1=455, x2=635, y2=365, amber=True),
    dict(x1=765, y1=485, x2=735, y2=485, dashed=True),
]
notes = [
    dict(x=500, y=28, text="The same image deployed twice: introspection belongs on the instance only your own tools reach", anchor="middle", bold=True),
    dict(x=500, y=542, text="Anonymous callers reach only the public instance. The contract check needs a schema, not a public endpoint.", anchor="middle", size=12, color="#555555"),
]
g.emit("17-public-vs-internal-endpoints", 1000, 560, bands=bands, nodes=nodes, edges=edges, notes=notes)
