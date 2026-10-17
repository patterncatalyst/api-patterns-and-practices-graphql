"""Spec for assets/diagrams/20-composition-pipeline.{svg,excalidraw}. Regenerate: python3 -I diagrams/20-composition-pipeline.py

Drawn from one run of examples/20-federation/verify.sh: the live `_service { sdl }`
of four subgraphs, two composer runs, two supergraph files and the two gateways that
load them. The ink box is the exit of a failed composition: the codes are the ones
verify.sh reads when it composes the two committed fixtures.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [dict(x=20, y=50, w=960, h=420, label="Composition is a build step: subgraph SDL in, one supergraph file out")]
nodes = [
    dict(x=40, y=90, w=190, h=60, style="box", lines=["cargo on Quarkus", "host 8302"]),
    dict(x=40, y=165, w=190, h=60, style="accent", lines=["handling on Python", "host 8305"]),
    dict(x=320, y=105, w=180, h=105, style="user", lines=["composer-a", "composeServices()", "exit 0", "writes supergraph-a"]),
    dict(x=590, y=122, w=190, h=70, style="accent", lines=["supergraph-a.graphql", "volume supergraph"]),
    dict(x=850, y=122, w=120, h=70, style="box", lines=["gateway-a", "host 8300"]),
    dict(x=40, y=315, w=190, h=60, style="accent", lines=["cargo on Python", "host 8303"]),
    dict(x=40, y=390, w=190, h=60, style="box", lines=["handling on Quarkus", "host 8304"]),
    dict(x=320, y=330, w=180, h=105, style="user", lines=["composer-b", "composeServices()", "exit 0", "writes supergraph-b"]),
    dict(x=590, y=347, w=190, h=70, style="accent", lines=["supergraph-b.graphql", "volume supergraph"]),
    dict(x=850, y=347, w=120, h=70, style="box", lines=["gateway-b", "host 8301"]),
    dict(x=320, y=236, w=180, h=70, style="ink", lines=["fixture run: exit 1", "FIELD_TYPE_MISMATCH", "INVALID_FIELD_SHARING"]),
]
edges = [
    dict(x1=230, y1=120, x2=320, y2=145, label="_service { sdl }", lx=-4, ly=-10),
    dict(x1=230, y1=195, x2=320, y2=175, label="_service { sdl }", lx=-4, ly=16),
    dict(x1=500, y1=157, x2=590, y2=157, amber=True),
    dict(x1=780, y1=157, x2=850, y2=157, amber=True, label="loads", lx=0, ly=-10),
    dict(x1=230, y1=345, x2=320, y2=370, label="_service { sdl }", lx=-4, ly=-10),
    dict(x1=230, y1=420, x2=320, y2=400, label="_service { sdl }", lx=-4, ly=16),
    dict(x1=500, y1=382, x2=590, y2=382, amber=True),
    dict(x1=780, y1=382, x2=850, y2=382, amber=True, label="loads", lx=0, ly=-10),
    dict(x1=410, y1=210, x2=410, y2=236, dashed=True),
]
notes = [
    dict(x=500, y=28, text="A failed composition stops the deploy before a gateway starts", anchor="middle", bold=True),
    dict(x=520, y=262, text="--file cargo=... --file handling=fixtures/...", size=11, color="#555555"),
    dict(x=520, y=282, text="nothing is written, so there is nothing for a gateway to load", size=11, color="#555555"),
]
g.emit("20-composition-pipeline", 1000, 490, bands=bands, nodes=nodes, edges=edges, notes=notes)
