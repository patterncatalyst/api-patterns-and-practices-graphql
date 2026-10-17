"""Spec for assets/diagrams/09-error-masking.{svg,excalidraw}. Regenerate: python3 -I diagrams/09-error-masking.py

Drawn from the PQR234 run in verify.sh: the shard name reaches the server log and
never the response.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=30, y=170, w=150, h=80, style="box", lines=["Source throws", "IllegalStateException", "or RuntimeError"]),
    dict(x=225, y=170, w=130, h=80, style="box", lines=["Resolver", "no catch block"]),
    dict(x=400, y=170, w=150, h=80, style="box", lines=["Engine error", "path and message", "original exception"]),
    dict(x=600, y=150, w=230, h=120, style="accent", lines=["Allowlist check", "SmallRye: show-runtime-", "exception-message", "Strawberry: should_mask", "(ExposedError)"]),
    dict(x=880, y=60, w=190, h=90, style="box", lines=["Exposed", "message and", "code SERVICE_UNAVAILABLE"]),
    dict(x=880, y=270, w=190, h=90, style="box", lines=["Masked", "Internal server error.", "no detail, no class name"]),
    dict(x=400, y=380, w=430, h=80, style="user", lines=["Server log", "full message, stack and time", "handling-primary-3 is kept here"]),
]
edges = [
    dict(x1=180, y1=210, x2=225, y2=210),
    dict(x1=355, y1=210, x2=400, y2=210),
    dict(x1=550, y1=210, x2=600, y2=210, amber=True),
    dict(x1=830, y1=180, x2=880, y2=110, amber=True, label="on the list", lx=-20, ly=-18),
    dict(x1=830, y1=240, x2=880, y2=310, label="anything else", lx=-30, ly=24),
    dict(x1=475, y1=250, x2=475, y2=380, dashed=True, label="always", lx=30, ly=0),
]
notes = [
    dict(x=550, y=28, text="Masking is an allowlist: only the errors a service chose to show reach the client", anchor="middle", bold=True),
    dict(x=550, y=490, text="Quarkus sends extensions.code null for a masked error (DeclaredErrorCodeProvider); Strawberry sends no extensions.", anchor="middle", size=12, color="#555555"),
]
g.emit("09-error-masking", 1100, 510, nodes=nodes, edges=edges, notes=notes)
