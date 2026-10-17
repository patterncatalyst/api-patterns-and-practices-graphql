"""Spec for assets/diagrams/03-scalar-coercion.{svg,excalidraw}. Regenerate: python3 -I diagrams/03-scalar-coercion.py"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

nodes = [
    dict(x=30, y=70, w=240, h=70, style="user", lines=["Literal in the document", 'completionTime: "2026-10-15T00:00:00Z"']),
    dict(x=30, y=250, w=240, h=70, style="user", lines=["Variable in the JSON", '{"t": "2026-10-15T02:00:00+02:00"}']),
    dict(x=340, y=70, w=170, h=70, style="box", lines=["parse literal", "the AST string value"]),
    dict(x=340, y=250, w=170, h=70, style="box", lines=["parse value", "the JSON string"]),
    dict(x=340, y=160, w=170, h=70, style="ghost", lines=["Rejected", "number, bad text, no offset", "request error, no data"]),
    dict(x=580, y=155, w=180, h=80, style="accent", lines=["Internal value", "Java Instant", "Python datetime in UTC"]),
    dict(x=820, y=155, w=140, h=80, style="box", lines=["serialize", "UTC, whole seconds,", "suffix Z"]),
    dict(x=820, y=275, w=140, h=70, style="user", lines=["JSON output", '"2026-10-15T00:00:00Z"']),
]
edges = [
    dict(x1=270, y1=105, x2=340, y2=105),
    dict(x1=270, y1=285, x2=340, y2=285),
    dict(x1=510, y1=105, x2=580, y2=175, amber=True),
    dict(x1=510, y1=285, x2=580, y2=215, amber=True, label="normalized to UTC", lx=34, ly=28),
    dict(x1=425, y1=140, x2=425, y2=160, dashed=True),
    dict(x1=425, y1=250, x2=425, y2=230, dashed=True),
    dict(x1=760, y1=195, x2=820, y2=195, amber=True),
    dict(x1=890, y1=235, x2=890, y2=275, amber=True),
]
notes = [
    dict(x=150, y=48, text="Input: two entry points", anchor="middle", bold=True),
    dict(x=670, y=130, text="Held as one internal value", anchor="middle", bold=True),
    dict(x=890, y=130, text="Output", anchor="middle", bold=True),
    dict(x=490, y=385, text="Result coercion is serialize; input coercion is parse value (variables) or parse literal (inline arguments).", anchor="middle", size=12, color="#555555"),
]
g.emit("03-scalar-coercion", 980, 400, nodes=nodes, edges=edges, notes=notes)
