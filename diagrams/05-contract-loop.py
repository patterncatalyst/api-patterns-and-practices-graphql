"""Spec for assets/diagrams/05-contract-loop.{svg,excalidraw}. Regenerate: python3 -I diagrams/05-contract-loop.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=385, w=960, h=125, label="Gates on the canonical SDL itself"),
]
nodes = [
    dict(x=20, y=80, w=190, h=70, style="user", lines=["Quarkus code", "@Type, @Query, @Description"]),
    dict(x=20, y=220, w=190, h=70, style="user", lines=["Strawberry code", "@strawberry.type, fields"]),
    dict(x=250, y=80, w=200, h=70, style="box", lines=["GET schema.graphql", "/graphql/schema.graphql, scalars on"]),
    dict(x=250, y=220, w=200, h=70, style="box", lines=["strawberry CLI", "export-schema app.schema:schema"]),
    dict(x=490, y=80, w=170, h=70, style="box", lines=["quarkus.graphql", "exported SDL"]),
    dict(x=490, y=220, w=170, h=70, style="box", lines=["python.graphql", "exported SDL"]),
    dict(x=710, y=130, w=270, h=100, style="accent", lines=["graphql-inspector diff", "live to canonical: extra or tighter", "canonical to live: changed, not absent"]),
    dict(x=710, y=20, w=270, h=60, style="box", lines=["contracts/schema/**/*.graphql", "canonical SDL"]),
    dict(x=710, y=290, w=270, h=70, style="box", lines=["Gate result", "pass, or FAIL naming the field"]),
    dict(x=380, y=430, w=220, h=60, style="box", lines=["contracts/schema/", "canonical SDL"]),
    dict(x=60, y=430, w=220, h=60, style="box", lines=["npm run lint", "descriptions, naming"]),
    dict(x=680, y=430, w=270, h=60, style="box", lines=["npm run breaking", "canonical vs origin/main"]),
]
edges = [
    dict(x1=210, y1=115, x2=250, y2=115),
    dict(x1=210, y1=255, x2=250, y2=255),
    dict(x1=450, y1=115, x2=490, y2=115, amber=True),
    dict(x1=450, y1=255, x2=490, y2=255, amber=True),
    dict(x1=660, y1=115, x2=710, y2=160, amber=True),
    dict(x1=660, y1=255, x2=710, y2=205, amber=True),
    dict(x1=845, y1=80, x2=845, y2=130, amber=True, label="both directions", lx=62, ly=-2),
    dict(x1=845, y1=230, x2=845, y2=290, amber=True),
    dict(x1=575, y1=150, x2=575, y2=220, dashed=True, bidir=True, label="same schema", lx=48, ly=-2),
    dict(x1=380, y1=460, x2=280, y2=460),
    dict(x1=600, y1=460, x2=680, y2=460),
]
notes = [
    dict(x=115, y=58, text="Code, per stack", anchor="middle", bold=True),
    dict(x=350, y=58, text="Export", anchor="middle", bold=True),
    dict(x=575, y=58, text="SDL file", anchor="middle", bold=True),
    dict(x=40, y=325, text="Both stacks stay code-first; the canonical SDL is the yardstick.", size=12, color="#555555"),
    dict(x=40, y=345, text="Drift is seeded into copies of each export and must fail the gate.", size=12, color="#555555"),
]
g.emit("05-contract-loop", 1000, 530, bands=bands, nodes=nodes, edges=edges, notes=notes)
