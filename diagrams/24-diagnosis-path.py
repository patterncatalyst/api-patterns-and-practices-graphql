"""Spec for assets/diagrams/24-diagnosis-path.{svg,excalidraw}. Regenerate: python3 -I diagrams/24-diagnosis-path.py

Drawn from one run of query DeliveryOfJkl for cargo JKL012 on the Python stack,
trace id 156c5bf9e9cc30502aad07ac2cec876b, sent as the caller's traceparent:
  response   data.cargo null; one error at ["cargo","delivery"], message
             "Internal server error.", extensions {"traceId": the id above}
  Tempo      spans POST /graphql, GraphQL Query: DeliveryOfJkl, GraphQL
             Resolving: cargo, GraphQL Resolving: delivery (status ERROR,
             exception event KeyError 'XXBAD'), three source.call
  Loki       {service_name="ch24-debugging-python"} | trace_id="<id>": one record,
             exception_type KeyError, exception_message XXBAD
  data       evt_10 UNLOAD at XXBAD on V200E; JKL012's second leg ends at XXBAD;
             the location source holds five codes and not XXBAD
The Quarkus stack gives the same path with java.util.NoSuchElementException
("no location XXBAD") and extensions {"code": null, "traceId": ...}.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=410, label="From a masked response to the data that caused it")]
nodes = [
    dict(x=40, y=100, w=215, h=150, style="user", lines=["1  The response", "data.cargo: null", "path: cargo, delivery", "Internal server error.", "extensions.traceId", "156c5bf9...c876b"]),
    dict(x=290, y=100, w=215, h=150, style="box", lines=["2  The trace in Tempo", "GraphQL Query: DeliveryOfJkl", "GraphQL Resolving: delivery", "status ERROR", "exception KeyError"]),
    dict(x=540, y=100, w=215, h=150, style="box", lines=["3  The record in Loki", "trace_id = the same id", "exception_type KeyError", "exception_message XXBAD"]),
    dict(x=790, y=100, w=170, h=150, style="accent", lines=["4  The data", "evt_10: UNLOAD", "at XXBAD", "leg 2 ends at XXBAD", "location source: no XXBAD"]),
    dict(x=540, y=320, w=215, h=95, style="accent", lines=["5  The fix", "the location owner adds XXBAD,", "or the derivation treats an", "unknown location as null"]),
    dict(x=790, y=320, w=170, h=95, style="ink", lines=["6  A regression test", "JKL012 delivery answers", "(Chapter 23)"]),
]
edges = [
    dict(x1=255, y1=175, x2=290, y2=175, amber=True, label="id", lx=0, ly=-8),
    dict(x1=505, y1=175, x2=540, y2=175, amber=True, label="same id", lx=0, ly=-8),
    dict(x1=755, y1=175, x2=790, y2=175, amber=True, label="XXBAD", lx=0, ly=-8),
    dict(x1=875, y1=250, x2=700, y2=320, label="names the cause", lx=60, ly=-8),
    dict(x1=755, y1=367, x2=790, y2=367, label="then", lx=0, ly=-8),
]
notes = [
    dict(x=500, y=28, text="The trace id in the error is the key to the trace, the log record and the data", anchor="middle", bold=True),
    dict(x=40, y=300, text="The client sees only step 1.", size=12, color="#555555"),
    dict(x=40, y=320, text="Steps 2 to 4 are server-side and need access", size=12, color="#555555"),
    dict(x=40, y=338, text="to the observability backend.", size=12, color="#555555"),
    dict(x=500, y=485, text="One run of DeliveryOfJkl on the Python stack. The Quarkus stack gives the same path with NoSuchElementException.", anchor="middle", size=12, color="#555555"),
]
g.emit("24-diagnosis-path", 1000, 510, bands=bands, nodes=nodes, edges=edges, notes=notes)
