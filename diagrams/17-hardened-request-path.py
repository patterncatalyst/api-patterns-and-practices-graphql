"""Spec for assets/diagrams/17-hardened-request-path.{svg,excalidraw}. Regenerate: python3 -I diagrams/17-hardened-request-path.py

The gates a request to a public instance passes, in order, and the refusal at each one.
Every refusal is a response observed by examples/17-transport-security/verify.sh:
  TLS         no CA: curl exit 60; TLS 1.2 client: Quarkus handshake alert (curl exit 35), Python 200
  CORS        preflight from https://evil.example: Quarkus 403, Python 400, no Access-Control-Allow-Origin
  Content-Type  text/plain, form, multipart POST: Quarkus 415, Python 400, zero source calls
  Body size   100 KB body: Quarkus 413; Python 200 (the limit is set at a fronting proxy)
  Parse       16000-token list: Quarkus "Unparseable input document" (graphql-java default 15000),
              Python "Document contains more than 5000 tokens"
  Validate    __schema / __type refused on both stacks, errors and no data (Quarkus: Introspection.enabledJvmWide(false), refused at execution start before the first resolver);
              a real and an unknown type name get the same answer; the misspelt field carries no "Did you mean"
  Execute     GHI345: code SERVICE_UNAVAILABLE; any other failure is masked
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

W, GAP, X0, Y, H = 128, 14, 20, 70, 86
RY, RH = 250, 150
gates = [
    ("TLS", ["handshake,", "certificate", "and protocol"]),
    ("CORS", ["origin check,", "preflight"]),
    ("Content-Type", ["JSON media", "type only"]),
    ("Body size", ["bytes before", "parsing"]),
    ("Parse", ["token limit", "on the document"]),
    ("Validate", ["introspection", "rule (Quarkus: at", "execution start)"]),
    ("Execute", ["resolvers,", "masked errors"]),
]
refusals = [
    ["handshake fails", "no CA: untrusted", "Quarkus: TLS 1.3", "only", "Python: 1.2 and up"],
    ["no Allow-Origin", "Quarkus: 403", "Python: 400", "(on the preflight)"],
    ["415 or 400", "Quarkus: 415", "Python: 400", "form and text/plain", "never run"],
    ["413 or 200", "Quarkus: 413 at 64K", "Python: 200; the", "limit is set at", "a fronting proxy"],
    ["errors, no data", "Quarkus: 15000", "tokens", "Python: 5000"],
    ["errors, no data", "__schema, __type", "refused on both;", "no \"Did you mean\""],
    ["message masked", "exposed codes pass;", "the rest become", "Internal server", "error."],
]
xs = [X0 + i * (W + GAP) for i in range(len(gates))]
nodes = []
for x, (title, lines) in zip(xs, gates):
    style = "accent" if title in ("Content-Type", "Validate") else "box"
    nodes.append(dict(x=x, y=Y, w=W, h=H, style=style, lines=[title] + lines))
for x, lines in zip(xs, refusals):
    nodes.append(dict(x=x, y=RY, w=W, h=RH, style="ghost", lines=lines))
edges = []
for i in range(len(gates) - 1):
    edges.append(dict(x1=xs[i] + W, y1=Y + H / 2, x2=xs[i + 1], y2=Y + H / 2))
for x in xs:
    edges.append(dict(x1=x + W / 2, y1=Y + H, x2=x + W / 2, y2=RY, dashed=True))
width = xs[-1] + W + 20
notes = [
    dict(x=width / 2, y=34, text="A request to a public instance passes seven gates; each refusal happens before the next gate runs", anchor="middle", bold=True),
    dict(x=width / 2, y=430, text="Responses observed with curl against both public instances. A refused form POST makes zero source calls, so no write happens.", anchor="middle", size=12, color="#555555"),
]
g.emit("17-hardened-request-path", width, 452, nodes=nodes, edges=edges, notes=notes)
