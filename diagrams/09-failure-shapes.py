"""Spec for assets/diagrams/09-failure-shapes.{svg,excalidraw}. Regenerate: python3 -I diagrams/09-failure-shapes.py

One failure, an unknown voyage, in three envelopes. Only the middle one is served;
the other two are sketches.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import generate_diagram as g  # noqa: E402

g.OUT = str(ROOT / "assets" / "diagrams")

bands = [
    dict(x=20, y=50, w=340, h=380, label="Top-level errors[]"),
    dict(x=380, y=50, w=340, h=380, label="Payload userErrors (served)"),
    dict(x=740, y=50, w=340, h=380, label="Result union (sketch)"),
]
nodes = [
    dict(x=40, y=90, w=300, h=120, style="accent", lines=["errors[0]", "message: unknown voyage", "extensions.code", "data: null"]),
    dict(x=40, y=240, w=300, h=100, style="box", lines=["Client branches on", "errors present, then", "extensions.code"]),
    dict(x=40, y=360, w=300, h=50, style="ghost", lines=["Counted by monitors as a failure"]),
    dict(x=400, y=90, w=300, h=120, style="accent", lines=["data.registerHandlingEvent", "handlingEvent: null", 'userErrors[0].code UNKNOWN_VOYAGE', 'field ["input","voyageNumber"]']),
    dict(x=400, y=240, w=300, h=100, style="box", lines=["Client branches on", "userErrors non-empty,", "then code and field"]),
    dict(x=400, y=360, w=300, h=50, style="ghost", lines=["No errors key; HTTP and monitors stay quiet"]),
    dict(x=760, y=90, w=300, h=120, style="accent", lines=["data.registerHandlingEvent", "__typename: ValidationFailed", "code UNKNOWN_VOYAGE", "field, message"]),
    dict(x=760, y=240, w=300, h=100, style="box", lines=["Client branches on", "__typename in an inline", "fragment per member"]),
    dict(x=760, y=360, w=300, h=50, style="ghost", lines=["Adding a member is a dangerous change"]),
]
notes = [
    dict(x=550, y=28, text="One failure, three envelopes", anchor="middle", bold=True),
    dict(x=550, y=454, text="The book serves the middle shape. The union is shown as SDL in the chapter and is not part of the example.", anchor="middle", size=12, color="#555555"),
]
g.emit("09-failure-shapes", 1100, 475, bands=bands, nodes=nodes, notes=notes)
