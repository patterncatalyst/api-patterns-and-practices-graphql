"""Spec for assets/diagrams/16-cache-policy-decision.{svg,excalidraw}. Regenerate: python3 -I diagrams/16-cache-policy-decision.py

The decision CachePolicy.java (@AfterExecute) and cache_policy.py (a Strawberry
SchemaExtension) make for every response, from the code in examples/16-caching.
The four tests run in the order drawn; any "no" ends in no-store.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=60, y=70, w=330, h=60, style="box", lines=["Is the request a GET?", "a POST body is not part of any cache key"]),
    dict(x=60, y=170, w=330, h=60, style="box", lines=["Did execution finish without errors?", "an error describes one request"]),
    dict(x=60, y=270, w=330, h=60, style="box", lines=["Are all root fields reference data?", "location, voyage, __typename"]),
    dict(x=60, y=370, w=330, h=60, style="box", lines=["Is there no Authorization header?", "what a caller may read can depend on who asks"]),
    dict(x=60, y=480, w=330, h=70, style="accent", lines=["Cache-Control:", "public, max-age=300"]),
    dict(x=640, y=250, w=330, h=90, style="accent", lines=["Cache-Control: no-store", "a no at any step keeps the", "response out of every shared cache"]),
]
edges = [
    dict(x1=225, y1=130, x2=225, y2=170, label="yes", lx=18, ly=0),
    dict(x1=225, y1=230, x2=225, y2=270, label="yes", lx=18, ly=0),
    dict(x1=225, y1=330, x2=225, y2=370, label="yes", lx=18, ly=0),
    dict(x1=225, y1=430, x2=225, y2=480, label="yes", lx=18, ly=0, amber=True),
    dict(x1=390, y1=100, x2=640, y2=270, label="no", lx=-70, ly=-40),
    dict(x1=390, y1=200, x2=640, y2=285, label="no", lx=-40, ly=-20),
    dict(x1=390, y1=300, x2=640, y2=300, label="no", lx=0, ly=-10),
    dict(x1=390, y1=400, x2=640, y2=325, label="no", lx=-30, ly=22),
]
notes = [
    dict(x=500, y=32, text="Deciding Cache-Control for one response", anchor="middle", bold=True),
    dict(x=640, y=380, text="A PersistedQueryNotFound refusal is no-store too:", size=12, color="#555555"),
    dict(x=640, y=400, text="the document may be registered a moment later.", size=12, color="#555555"),
]
g.emit("16-cache-policy-decision", 1000, 580, nodes=nodes, edges=edges, notes=notes)
