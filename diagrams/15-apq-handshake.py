"""Spec for assets/diagrams/15-apq-handshake.{svg,excalidraw}. Regenerate: python3 -I diagrams/15-apq-handshake.py

Drawn from one run of examples/15-persisted-queries on the Quarkus APQ instance
(port 8250), with the CargoDetail document of verify.sh (580 characters, three
fragments) and variables {"id":"DEF456"}. The byte counts are measured with
curl's size_upload and size_download: the three request bodies, the 204-byte
request target of the GET (no body), and the response bodies. The Python
instance answers the same way, with 111 bytes for the first response because it
adds "data": null.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=1060, h=130, label="Round trip 1: the client sends the hash alone, and the store is empty"),
    dict(x=20, y=200, w=1060, h=130, label="Round trip 2: the client sends the hash and the text, and the server stores it"),
    dict(x=20, y=350, w=1060, h=130, label="Round trip 3: the hash alone again, this time as a GET with no body"),
]
nodes = [
    dict(x=45, y=88, w=290, h=70, style="user", lines=["POST /graphql", "163 bytes: variables and sha256Hash"]),
    dict(x=405, y=88, w=290, h=70, style="box", lines=["look the hash up", "not in the manifest or the store"]),
    dict(x=765, y=88, w=290, h=70, style="accent", lines=["200 PersistedQueryNotFound", "99 bytes, no data"]),
    dict(x=45, y=238, w=290, h=70, style="user", lines=["POST /graphql", "756 bytes: text, variables, sha256Hash"]),
    dict(x=405, y=238, w=290, h=70, style="accent", lines=["recompute sha256(text)", "match: store the text, then execute"]),
    dict(x=765, y=238, w=290, h=70, style="box", lines=["200 data", "2,412 bytes"]),
    dict(x=45, y=388, w=290, h=70, style="user", lines=["GET /graphql?variables&extensions", "204 bytes of URL, no body"]),
    dict(x=405, y=388, w=290, h=70, style="accent", lines=["store hit: reuse the text", "execute as if it had been sent"]),
    dict(x=765, y=388, w=290, h=70, style="box", lines=["200 data", "2,412 bytes"]),
]
edges = [
    dict(x1=335, y1=123, x2=405, y2=123),
    dict(x1=695, y1=123, x2=765, y2=123),
    dict(x1=335, y1=273, x2=405, y2=273, amber=True),
    dict(x1=695, y1=273, x2=765, y2=273),
    dict(x1=335, y1=423, x2=405, y2=423),
    dict(x1=695, y1=423, x2=765, y2=423),
]
notes = [
    dict(x=550, y=28, text="Apollo's persisted-query handshake: three round trips for one document", anchor="middle", bold=True),
    dict(x=550, y=504, text="The plain POST of the same document and variables is 624 bytes. After registration each request is 163 bytes, or a URL.", anchor="middle", size=12, color="#555555"),
]
g.emit("15-apq-handshake", 1100, 530, bands=bands, nodes=nodes, edges=edges, notes=notes)
