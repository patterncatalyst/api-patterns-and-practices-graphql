"""Spec for assets/diagrams/15-apq-vs-trusted.{svg,excalidraw}. Regenerate: python3 -I diagrams/15-apq-vs-trusted.py

The two modes of examples/15-persisted-queries, side by side, as verify.sh
asserts them on ports 8250/8251 (apq) and 8252/8253 (trusted).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=520, h=420, label="APQ: clients register documents at run time"),
    dict(x=560, y=50, w=520, h=420, label="Trusted documents: the build registers them"),
]
rows = [
    ("Who registers", 90),
    ("What the server accepts", 190),
    ("What an attacker can do", 290),
    ("What a cache or gateway sees", 390),
]
apq = [
    ["Any client, with the hash and the text", "the first request pays the extra bytes"],
    ["Any text that matches its own hash", "a hash alone must have been registered"],
    ["Register any text, fill the bounded store", "evict the entries real clients rely on"],
    ["Short GET URLs once registered", "a miss costs one more round trip"],
]
trusted = [
    ["The build pipeline, from the client's manifest", "the server loads it at start"],
    ["Manifest documents, by hash or by exact text", "unknown text: PERSISTED_QUERY_REQUIRED"],
    ["Nothing new runs and nothing is stored", "introspection text is refused too"],
    ["Short GET URLs, no registration miss", "the manifest must ship before the client"],
]
nodes = []
for (title, y), a, t in zip(rows, apq, trusted):
    nodes.append(dict(x=45, y=y, w=470, h=84, style="box" if title != "What an attacker can do" else "accent", lines=[title, a[0], a[1]]))
    nodes.append(dict(x=585, y=y, w=470, h=84, style="box" if title != "What an attacker can do" else "accent", lines=[title, t[0], t[1]]))
notes = [
    dict(x=550, y=28, text="Two uses of the same hash: a bandwidth tool and an allowlist", anchor="middle", bold=True),
    dict(x=550, y=494, text="APQ is not a security control. Trusted mode is one, and Chapter 14's limits remain the backstop.", anchor="middle", size=12, color="#555555"),
]
g.emit("15-apq-vs-trusted", 1100, 520, bands=bands, nodes=nodes, edges=[], notes=notes)
