"""Spec for assets/diagrams/16-cache-layers.{svg,excalidraw}. Regenerate: python3 -I diagrams/16-cache-layers.py

The four places a GraphQL service keeps an answer, in the order a request meets
them, with what each layer keys on and what removes an entry. The edge and
server columns are what examples/16-caching runs (nginx proxy_cache; quarkus-cache
and cachetools). The client cache is Chapter 22's subject and is prose only here.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=30, y=70, w=235, h=150, style="user", lines=["1. Client cache", "key: __typename + id", "removed by: a newer response", "for the same object", "(Chapter 22)"]),
    dict(x=305, y=70, w=235, h=150, style="accent", lines=["2. Edge: nginx proxy_cache", "key: method + URL", "stores what Cache-Control allows", "skips: Authorization, no-store", "removed by: max-age"]),
    dict(x=580, y=70, w=235, h=150, style="accent", lines=["3. Server: field caches", "key: voyage no., UN/LOCODE,", "tracking id", "removed by: TTL, or a write", "(registerHandlingEvent)"]),
    dict(x=855, y=70, w=215, h=150, style="box", lines=["4. Source: the owners", "booking, routing, voyage,", "location, handling", "the system of record", "every call is logged"]),
    dict(x=580, y=260, w=490, h=60, style="ghost", lines=["Chapter 13 loader cache: one request, then gone", "it sits above layer 3 and shares nothing between requests"]),
]
edges = [
    dict(x1=265, y1=145, x2=305, y2=145, label="GET", lx=0, ly=-8),
    dict(x1=540, y1=145, x2=580, y2=145, label="miss", lx=0, ly=-8),
    dict(x1=815, y1=145, x2=855, y2=145, label="miss", lx=0, ly=-8),
]
notes = [
    dict(x=550, y=32, text="Four places to keep an answer, nearest the caller first", anchor="middle", bold=True),
    dict(x=30, y=300, text="Layer 2 can see only the URL.", size=12, color="#555555"),
    dict(x=30, y=320, text="Layer 3 sees keys and ignores who asked.", size=12, color="#555555"),
    dict(x=30, y=345, text="A hit at any layer ends the request there; the layers below never see it.", size=12, color="#555555"),
]
g.emit("16-cache-layers", 1100, 370, nodes=nodes, edges=edges, notes=notes)
