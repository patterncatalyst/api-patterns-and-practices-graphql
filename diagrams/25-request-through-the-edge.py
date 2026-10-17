"""Spec for assets/diagrams/25-request-through-the-edge.{svg,excalidraw}. Regenerate: python3 -I diagrams/25-request-through-the-edge.py

Drawn from one run of examples/25-docker-compose against the Python stack. Top:
ListCargos sent to the edge on port 8351 with traceparent
00-e317abd0a65a4ba25a30bfb67ccda8fb-00f067aa0ba902b7-01. The backend made two
source calls, booking.listCargos and booking.getCargos for six keys, and the
error at edges[5].node carries the trace id, which finds the trace in Tempo and
the exception record in Loki. Bottom: a 100 KB body stops at the edge with 413.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=960, h=290, label="A traced request"),
    dict(x=20, y=360, w=960, h=130, label="A refused request"),
]
nodes = [
    dict(x=40, y=100, w=160, h=80, style="user", lines=["client", "traceparent 00-e317abd0...", "-00f067aa0ba902b7-01"]),
    dict(x=240, y=100, w=170, h=80, style="accent", lines=["edge :8351", "TLS 1.3, /graphql only,", "body under 64k"]),
    dict(x=460, y=100, w=160, h=80, style="box", lines=["python", "query ListCargos", "cargos(first: 10)"]),
    dict(x=670, y=100, w=290, h=80, style="box", lines=["booking source", "listCargos, key *", "getCargos, 6 keys in one call; GHI345 fails"]),
    dict(x=240, y=220, w=190, h=90, style="accent", lines=["200, 6 edges, node null at 5", "SERVICE_UNAVAILABLE", "extensions.traceId e317abd0..."]),
    dict(x=480, y=220, w=200, h=90, style="box", lines=["Tempo :8353", "GraphQL Query: ListCargos", "source.call spans, same id"]),
    dict(x=730, y=220, w=220, h=90, style="box", lines=["Loki :8355", "ERROR record for the", "booking failure, same trace_id"]),
    dict(x=40, y=395, w=160, h=70, style="user", lines=["client", "100 KB body"]),
    dict(x=240, y=395, w=170, h=70, style="accent", lines=["edge :8351", "client_max_body_size 64k"]),
    dict(x=460, y=395, w=230, h=70, style="ink", lines=["413 Request Entity Too Large", "upstream=- in the edge log"]),
    dict(x=740, y=395, w=210, h=70, style="ghost", lines=["python", "source-call log stays empty"]),
]
edges = [
    dict(x1=200, y1=140, x2=240, y2=140),
    dict(x1=410, y1=140, x2=460, y2=140, label="traceparent", lx=0, ly=-14),
    dict(x1=620, y1=140, x2=670, y2=140),
    dict(x1=325, y1=180, x2=325, y2=220, label="response", lx=34, ly=0),
    dict(x1=430, y1=265, x2=480, y2=265, amber=True, label="id", lx=0, ly=-14),
    dict(x1=680, y1=265, x2=730, y2=265, amber=True, label="same id", lx=0, ly=-14),
    dict(x1=200, y1=430, x2=240, y2=430),
    dict(x1=410, y1=430, x2=460, y2=430, amber=True),
    dict(x1=690, y1=430, x2=740, y2=430, dashed=True, label="not reached", lx=0, ly=-14),
]
notes = [
    dict(x=500, y=28, text="The edge decides first; the trace id follows the request to the backends of the tier", anchor="middle", bold=True),
    dict(x=500, y=514, text="A request that passes the edge keeps its traceparent. A request the edge refuses never creates a span in the backend.", anchor="middle", size=12, color="#555555"),
]
g.emit("25-request-through-the-edge", 1000, 540, bands=bands, nodes=nodes, edges=edges, notes=notes)
