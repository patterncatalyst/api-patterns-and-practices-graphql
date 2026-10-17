"""Spec for assets/diagrams/27-request-defences.{svg,excalidraw}. Regenerate: python3 -I diagrams/27-request-defences.py

Drawn from one run of examples/27-final-project. A request meets the defences in order,
and each one's refusal is the answer the run recorded: 413 at the edge, a failed
handshake below TLS 1.3, HTTP 401 for a token for another audience, the cost message
"maximum query complexity exceeded 7651 > 1000" with no data and no source call,
UNAUTHENTICATED or FORBIDDEN at the field's path, and a null for a cargo that is not
the caller's. The success path reaches the batched sources and returns extensions.traceId
on any execution error.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=140, label="Before GraphQL runs"),
    dict(x=20, y=205, w=960, h=140, label="Before any resolver runs"),
    dict(x=20, y=360, w=960, h=160, label="While the operation runs"),
]
nodes = [
    dict(x=40, y=95, w=150, h=70, style="accent", lines=["1 TLS 1.3", "edge listener"]),
    dict(x=250, y=95, w=150, h=70, style="accent", lines=["2 body limit", "64k at the edge"]),
    dict(x=460, y=95, w=150, h=70, style="accent", lines=["3 token", "signature, iss, aud, exp"]),
    dict(x=670, y=95, w=290, h=70, style="ink", lines=["refusals: TLS 1.2 handshake fails;", "413; 401 + WWW-Authenticate Bearer"]),
    dict(x=40, y=250, w=150, h=70, style="box", lines=["4 token limit", "5000 tokens"]),
    dict(x=250, y=250, w=150, h=70, style="box", lines=["5 depth + aliases", "validation rules"]),
    dict(x=460, y=250, w=150, h=70, style="box", lines=["6 cost", "budget 1000"]),
    dict(x=670, y=250, w=290, h=70, style="ink", lines=["refusal: 200, no data, 1 error", "maximum query complexity exceeded", "7651 > 1000; 0 source calls"]),
    dict(x=40, y=410, w=150, h=80, style="box", lines=["7 operation", "UNAUTHENTICATED at", "the root field"]),
    dict(x=250, y=410, w=150, h=80, style="box", lines=["8 object", "a cargo of another", "shipper is null"]),
    dict(x=460, y=410, w=150, h=80, style="box", lines=["9 field", "FORBIDDEN at", "registrationTime"]),
    dict(x=670, y=410, w=140, h=80, style="accent", lines=["10 sources", "batched: 8 calls", "(Quarkus), 6 (Python)"]),
    dict(x=840, y=410, w=120, h=80, style="accent", lines=["11 masking", "extensions.", "traceId"]),
]
edges = [
    dict(x1=190, y1=130, x2=250, y2=130),
    dict(x1=400, y1=130, x2=460, y2=130),
    dict(x1=610, y1=130, x2=670, y2=130, dashed=True, label="refused", lx=0, ly=-12),
    dict(x1=535, y1=165, x2=115, y2=250, amber=True, label="GraphQL", lx=0, ly=0),
    dict(x1=190, y1=285, x2=250, y2=285),
    dict(x1=400, y1=285, x2=460, y2=285),
    dict(x1=610, y1=285, x2=670, y2=285, dashed=True, label="refused", lx=0, ly=-12),
    dict(x1=535, y1=320, x2=115, y2=410, amber=True, label="executes", lx=0, ly=0),
    dict(x1=190, y1=450, x2=250, y2=450),
    dict(x1=400, y1=450, x2=460, y2=450),
    dict(x1=610, y1=450, x2=670, y2=450),
    dict(x1=810, y1=450, x2=840, y2=450),
]
notes = [
    dict(x=500, y=28, text="A request meets each defence in order; a refusal stops it there", anchor="middle", bold=True),
    dict(x=500, y=542, text="Values from verify.sh: the answer each defence gives is what the script asserts on both stacks.", anchor="middle", size=12, color="#555555"),
]
g.emit("27-request-defences", 1000, 565, bands=bands, nodes=nodes, edges=edges, notes=notes)
