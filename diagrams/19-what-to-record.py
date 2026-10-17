"""Spec for assets/diagrams/19-what-to-record.{svg,excalidraw}. Regenerate: python3 -I diagrams/19-what-to-record.py

What both stacks record and what they leave out, as verify.sh asserts it: the
operation name, the operation type, the field coordinate, error.code, client.name
and source.name/source.operation are recorded; variable values, resolver
arguments (no graphql.param.* attribute on any span), credentials and owner
lists are not. A literal in a document is replaced by ? in the Quarkus span and
recorded as sent in the Python span, so values travel as variables.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=470, h=330, label="Record: a small set of names"),
    dict(x=510, y=50, w=470, h=330, label="Leave out: anything that is a value"),
    dict(x=20, y=395, w=960, h=75, label="Label cardinality", fill="#ffffff"),
]
nodes = [
    dict(x=40, y=88, w=430, h=50, style="accent", lines=["operation name and type", "TrackCargo, query"]),
    dict(x=40, y=146, w=430, h=50, style="accent", lines=["field coordinate", "Itinerary.finalArrivalDate"]),
    dict(x=40, y=204, w=430, h=50, style="accent", lines=["error code", "SERVICE_UNAVAILABLE, BAD_USER_INPUT"]),
    dict(x=40, y=262, w=430, h=50, style="accent", lines=["client name", "the X-Client-Name header, or unknown"]),
    dict(x=40, y=320, w=430, h=50, style="accent", lines=["source name and operation", "booking.getCargos"]),
    dict(x=530, y=88, w=430, h=50, style="ghost", lines=["variable values", "ABC123 in {\"id\": \"ABC123\"}"]),
    dict(x=530, y=146, w=430, h=50, style="ghost", lines=["resolver arguments", "no graphql.param.* attribute"]),
    dict(x=530, y=204, w=430, h=50, style="ghost", lines=["credentials", "the Authorization header, tokens"]),
    dict(x=530, y=262, w=430, h=50, style="ghost", lines=["owner lists and personal data", "shipper names, booking owners"]),
    dict(x=530, y=320, w=430, h=50, style="ghost", lines=["literals in a document", "replaced by ? on Quarkus; send values as variables"]),
    dict(x=40, y=420, w=270, h=36, style="box", lines=["label: operation name (tens of values)"]),
    dict(x=355, y=420, w=270, h=36, style="box", lines=["label: field coordinate, error code"]),
    dict(x=670, y=420, w=290, h=36, style="ink", lines=["not a label: document, tracking id"]),
]
edges = []
notes = [
    dict(x=500, y=28, text="Record the shape of a request; keep its values out", anchor="middle", bold=True),
    dict(x=500, y=490, text="Every distinct label value is a new time series in Prometheus. A tracking id would make one per cargo.", anchor="middle", size=12, color="#555555"),
]
g.emit("19-what-to-record", 1000, 510, bands=bands, nodes=nodes, edges=edges, notes=notes)
